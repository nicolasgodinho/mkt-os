"""Meeting intelligence pipelines (docs/03 journey D; ADR 0003).

* `meeting.extract.v1`: the transcript (untrusted evidence) goes to the `reasoning` profile, which
  may only *propose* items. The database writes them as `meeting_proposals` in the completion
  transaction; people decide what enters the Client Brain (docs/11 invariants 4 and 5).
* `meeting.transcribe.v1`: the recording referenced by the meeting is read from inside
  `JMOS_MEDIA_ROOT` only, and transcribed by the local transcriber.

Neither handler writes anything itself: the returned output is validated against the job contract
and stored by the database through the lease-fenced completion function.
"""

from __future__ import annotations

import importlib
import json
import re
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, cast

from jmos_worker.handlers import Handler, JobContext
from jmos_worker.models import Evidence, ModelAdapter, build_messages
from jmos_worker.queue import JobError, MeetingContext

MAX_PROPOSALS = 100
# Transcripts are split so each request fits comfortably in a local model's context window.
CHUNK_CHARACTERS = 24_000
KINDS = frozenset({"fact", "decision", "rule", "insight", "task"})
RULE_TYPES = frozenset({"MUST", "MUST_NOT", "PREFER", "AVOID"})
# Mirrors app.is_recording_ref in the database (defence in depth).
RECORDING_REF = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._ -]*(/[A-Za-z0-9][A-Za-z0-9._ -]*)*$")

EXTRACTION_INSTRUCTIONS = """You extract structured marketing knowledge from a client meeting \
transcript for a marketing agency. Your output is only a list of PROPOSALS that people will review.

Reply with one JSON object: {"proposals": [ ... ]}. Each proposal is an object with:
- "kind": "fact" | "decision" | "rule" | "insight" | "task"
- "statement": one self-contained sentence in the transcript's language
- "confidence": number from 0 to 1
- "evidence_quote": a short exact quote from the transcript that supports it
- "time_ref": a timestamp or position if the transcript has one
- for kind "rule" only: "rule_type" ("MUST" | "MUST_NOT" | "PREFER" | "AVOID") and a short
  lowercase "subject" naming what the rule is about (e.g. "preco", "cta", "emoji")

Rules of extraction:
- Only propose what the participants explicitly stated. Never invent.
- Hypotheticals, ideas and doubts ("talvez", "maybe", "could we", "vamos pensar") are NOT facts,
  decisions or rules: propose them as "insight" or "task" with confidence 0.5 or lower.
- Use "rule" only for explicit, lasting instructions about how the client's marketing must or must
  not be done; use MUST/MUST_NOT only for firm obligations or prohibitions.
- Use "task" for action items and open questions.
- At most 100 proposals. If nothing qualifies, reply {"proposals": []}."""


def _text(value: object, limit: int) -> str | None:
    if not isinstance(value, str):
        return None
    cleaned = value.strip()
    return cleaned[:limit] if cleaned else None


def normalize_proposals(raw: object) -> list[dict[str, object]]:
    """Keeps only well-formed proposals in contract shape; anything else is dropped."""
    items = raw.get("proposals") if isinstance(raw, dict) else None
    if not isinstance(items, list):
        raise JobError(
            "model_output_invalid", "the model answer has no proposals list", retryable=False
        )
    proposals: list[dict[str, object]] = []
    for item in items:
        if len(proposals) >= MAX_PROPOSALS:
            break
        if not isinstance(item, dict):
            continue
        kind = item.get("kind")
        statement = _text(item.get("statement"), 2000)
        if kind not in KINDS or statement is None:
            continue
        proposal: dict[str, object] = {"kind": kind, "statement": statement}
        confidence = item.get("confidence")
        if isinstance(confidence, int | float) and not isinstance(confidence, bool):
            proposal["confidence"] = round(min(max(float(confidence), 0.0), 1.0), 2)
        for key, limit in (("evidence_quote", 1000), ("time_ref", 50)):
            value = _text(item.get(key), limit)
            if value is not None:
                proposal[key] = value
        if kind == "rule":
            rule_type = item.get("rule_type")
            if not isinstance(rule_type, str) or rule_type.upper() not in RULE_TYPES:
                continue  # a rule without a valid type cannot be reviewed as a rule
            proposal["rule_type"] = rule_type.upper()
            subject = _text(item.get("subject"), 80)
            if subject is not None:
                proposal["subject"] = subject.lower()
        proposals.append(proposal)
    return proposals


def _chunks(text: str, size: int = CHUNK_CHARACTERS) -> list[str]:
    """Splits on line boundaries where possible so statements are not cut in half."""
    chunks: list[str] = []
    current: list[str] = []
    length = 0
    for line in text.splitlines(keepends=True):
        while len(line) > size:  # a single huge line
            chunks.append(line[:size])
            line = line[size:]
        if length + len(line) > size and current:
            chunks.append("".join(current))
            current, length = [], 0
        current.append(line)
        length += len(line)
    if current:
        chunks.append("".join(current))
    return chunks


def _meeting(context: JobContext) -> MeetingContext:
    meeting = context.meeting_for_job()
    if meeting is None:
        # The lease is gone (or the job no longer names a meeting): another attempt owns it.
        raise JobError("lease_lost", "the meeting is not readable under this lease", retryable=True)
    return meeting


def meeting_extract_v1(adapter: ModelAdapter) -> Handler:
    def handle(context: JobContext, _payload: Mapping[str, object]) -> dict[str, object]:
        meeting = _meeting(context)
        if not meeting.transcript:
            raise JobError("transcript_missing", "the meeting has no transcript", retryable=False)
        profile = context.job.model_profile
        if not profile:
            raise JobError(
                "model_profile_missing", "the job declares no model profile", retryable=False
            )

        proposals: list[dict[str, object]] = []
        chunks = _chunks(meeting.transcript)
        for index, chunk in enumerate(chunks, start=1):
            if index > 1 and not context.extend_lease():
                raise JobError("lease_lost", "lease lost between transcript chunks", retryable=True)
            evidence = Evidence(
                source_id=f"meeting:{meeting.meeting_id}:revision:{meeting.transcript_revision}",
                trust_level="FIRST_PARTY",
                text=chunk,
            )
            task = (
                f"Meeting: {meeting.title}. Transcript part {index} of {len(chunks)}. "
                "Extract the proposals from the evidence block."
            )
            reply = adapter.chat_json(
                profile, build_messages(EXTRACTION_INSTRUCTIONS, task, [evidence])
            )
            try:
                answer = json.loads(reply.content)
            except ValueError:
                raise JobError(
                    "model_output_invalid", "the model did not answer with JSON", retryable=False
                ) from None
            proposals.extend(normalize_proposals(answer))
        return {"proposals": proposals[:MAX_PROPOSALS]}

    return handle


# ---------------------------------------------------------------------------
# Transcription
# ---------------------------------------------------------------------------
@dataclass(frozen=True, slots=True)
class Transcript:
    text: str
    language: str | None
    segments: Sequence[tuple[int, int, str]]  # (start_ms, end_ms, text)


class Transcriber(Protocol):
    def transcribe(self, path: Path, on_progress: Callable[[], None]) -> Transcript: ...


def resolve_recording(media_root: Path | None, recording_ref: str | None) -> Path:
    """The recording file, guaranteed to be inside the media root (symlinks resolved)."""
    if media_root is None:
        raise JobError(
            "media_root_not_configured", "JMOS_MEDIA_ROOT is not configured", retryable=False
        )
    if not recording_ref or not RECORDING_REF.match(recording_ref) or len(recording_ref) > 500:
        raise JobError(
            "recording_ref_invalid", "the recording reference is invalid", retryable=False
        )
    root = media_root.resolve(strict=True)
    try:
        path = (root / recording_ref).resolve(strict=True)
    except (FileNotFoundError, NotADirectoryError):
        raise JobError(
            "recording_not_found", "the recording is not in the media root", retryable=False
        ) from None
    if not path.is_relative_to(root) or not path.is_file():
        raise JobError(
            "recording_outside_media_root",
            "the recording resolves outside the media root",
            retryable=False,
        )
    return path


class FasterWhisperTranscriber:
    """faster-whisper on the local GPU/CPU (optional extra `transcription`)."""

    def __init__(self, model: str, *, device: str = "auto") -> None:
        self._model_name = model
        self._device = device
        self._model: object | None = None

    def transcribe(self, path: Path, on_progress: Callable[[], None]) -> Transcript:
        if self._model is None:
            try:
                module = importlib.import_module("faster_whisper")
            except ImportError:
                raise JobError(
                    "transcription_unavailable",
                    "faster-whisper is not installed (pip install '.[transcription]')",
                    retryable=False,
                ) from None
            self._model = module.WhisperModel(self._model_name, device=self._device)
        model = cast(Callable[..., tuple[object, object]], getattr(self._model, "transcribe"))  # noqa: B009
        segments_iter, info = model(str(path), vad_filter=True)
        segments: list[tuple[int, int, str]] = []
        texts: list[str] = []
        for index, segment in enumerate(cast(list[object], segments_iter)):
            text = str(getattr(segment, "text", "")).strip()
            start = int(float(getattr(segment, "start", 0.0)) * 1000)
            end = int(float(getattr(segment, "end", 0.0)) * 1000)
            segments.append((start, end, text))
            texts.append(text)
            if index % 50 == 49:
                on_progress()
        language = getattr(info, "language", None)
        return Transcript(
            text=" ".join(t for t in texts if t),
            language=language if isinstance(language, str) else None,
            segments=segments,
        )


def meeting_transcribe_v1(transcriber: Transcriber, media_root: Path | None) -> Handler:
    def handle(context: JobContext, _payload: Mapping[str, object]) -> dict[str, object]:
        meeting = _meeting(context)
        path = resolve_recording(media_root, meeting.recording_ref)

        def keep_lease() -> None:
            if not context.extend_lease():
                raise JobError("lease_lost", "lease lost during transcription", retryable=True)

        result = transcriber.transcribe(path, keep_lease)
        text = result.text.strip()[:500_000]
        if not text:
            raise JobError("transcript_empty", "the recording produced no speech", retryable=False)
        output: dict[str, object] = {
            "text": text,
            "segments": [
                {"start_ms": max(start, 0), "end_ms": max(end, 0), "text": segment[:5000]}
                for start, end, segment in list(result.segments)[:20_000]
            ],
        }
        if result.language:
            output["language"] = result.language[:20]
        return output

    return handle
