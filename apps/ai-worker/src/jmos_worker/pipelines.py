"""The handler set a worker advertises, built from what is configured on this machine."""

from __future__ import annotations

from pathlib import Path

from jmos_worker.handlers import DEFAULT_HANDLERS, Handler, ai_model_check_v1
from jmos_worker.meetings import Transcriber, meeting_extract_v1, meeting_transcribe_v1
from jmos_worker.models import ModelAdapter


def build_handlers(
    adapter: ModelAdapter | None,
    *,
    transcriber: Transcriber | None = None,
    media_root: Path | None = None,
) -> dict[str, Handler]:
    """Model jobs need a model adapter; transcription needs a transcriber (and a media root)."""
    handlers = dict(DEFAULT_HANDLERS)
    if adapter is not None:
        handlers["ai.model_check.v1"] = ai_model_check_v1(adapter)
        handlers["meeting.extract.v1"] = meeting_extract_v1(adapter)
    if transcriber is not None:
        handlers["meeting.transcribe.v1"] = meeting_transcribe_v1(transcriber, media_root)
    return handlers
