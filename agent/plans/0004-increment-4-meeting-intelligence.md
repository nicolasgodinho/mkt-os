# ExecPlan 0004 — Increment 4: Meeting intelligence

**Status:** approved under Nicolas's standing instruction (2026-10-02), so it runs autonomously. Decisions are recorded here, in the TEST_SPEC README and in ADR 0003.

**Spec anchor:** docs/13, Increment 4:
- Source file reference;
- transcription adapter;
- extraction schema;
- review screen;
- promotion to knowledge.

**Contract:** `tests/acceptance/increment-4/` (PR nicolasgodinho/mkt-os#16) and ADR 0003. When this plan and the tests disagree, the tests win.

## Goal

Implement docs/03 journey D end to end:

**meeting → transcript (pasted, or transcribed by the local worker) → structured extraction by the local model → human review → accepted items enter the Client Brain as proposed knowledge.**

Throughout:
- every step is audited;
- every item carries provenance (the meeting's Source);
- no model output ever becomes active knowledge or an active rule.

## Decisions

These are frozen in the README and in ADR 0003.

1. Every meeting owns a FIRST_PARTY `meeting` Source.
2. Model output only becomes `meeting_proposals`.
   - Accepting a proposal creates **proposed** knowledge through the Increment 2 API.
   - Approval and activation remain separate steps.
3. The worker reads and writes through three job-scoped, lease-fenced `worker.*` functions. Domain rows are written in the completion transaction, so delivery is exactly-once in effect.
4. Units of work are idempotent:
   - extraction: per transcript revision;
   - transcription: per recording reference.
5. Until Drive sync exists, a recording is a relative path under the worker's `JMOS_MEDIA_ROOT`.
6. Task and question proposals cannot be promoted until v0.2. They can only be rejected.
7. All meeting data is internal-only.

## In scope

**Migration `20261002140000_meeting_intelligence.sql`.** The prototype proven by the TEST_SPEC.

**`packages/core` contracts.** `meeting.extract.v1` and `meeting.transcribe.v1` (zod), with JSON Schema generated for the worker.

**Worker:**
- **Queue.** `JobQueue` gains `meeting_for_job` and a domain completion. `complete()` routes:
  - `meeting.extract.v1` → `worker.complete_meeting_extraction`;
  - `meeting.transcribe.v1` → `worker.complete_meeting_transcription`;
  - everything else → `worker.complete_job`.
- **`meeting.extract.v1` handler:**
  - reads the transcript through the lease;
  - builds messages that keep instructions separate from the transcript, which is untrusted evidence;
  - calls the `reasoning` profile;
  - parses JSON, normalizes it to the contract and caps it at 100 items.
  - Non-JSON output → `model_output_invalid` (permanent).
  - The instructions demand explicit statements only, label hypotheticals ("talvez", "maybe") as insights or tasks with low confidence, and never invent subjects.
- **`meeting.transcribe.v1` handler:**
  - A `Transcriber` protocol, with `FasterWhisperTranscriber` behind an **optional** extra (`transcription`, not installed in CI).
  - The recording path is resolved under `JMOS_MEDIA_ROOT` with `resolve()` + `is_relative_to` (symlink-safe).
  - Missing root, missing file or missing library → permanent errors with clear codes.
- **Runner.** Database `DataError` on completion is mapped to `result_rejected` (permanent).

**Web.** "Reuniões" in the client context:
- `/w/[ws]/clients/[id]/meetings`: list and creation form (title, start/end, participants one per line, optional recording reference).
- `/w/[ws]/clients/[id]/meetings/[meetingId]`: the review screen (docs/07 §11):
  - meeting data and the processing status, with the latest job status from the job center;
  - the transcript, with paste/edit;
  - the "Transcrever gravação" and "Extrair conhecimento" actions;
  - proposals grouped by kind, each with confidence, evidence quote and time reference, and Aceitar / Editar e aceitar / Rejeitar;
  - accepted items link to the Client Brain, where approval and activation happen.

**Seed.** One meeting for Cliente Demo A with a transcript and a completed extraction with proposals, so the review screen has data without a worker.

**Tests:**
- builder pgTAP `060_meeting_intelligence`;
- pytest for the handlers (fake model and fake transcriber), media-root confinement and the queue routing;
- an integration test that runs extraction against real Postgres with a stub model and redelivery;
- Vitest;
- E2E: create a meeting and paste a transcript; request extraction (it stays queued); review the seeded proposals (accept, then see the item in the Brain as proposed; reject); a client user gets 404.

## Non-goals (deferred)

| Item | Destination |
|---|---|
| Drive-backed recordings and documents | Increment 8 |
| Task promotion | v0.2 |
| Speaker diarization, VRAM model manager | When needed on the real GPU |
| Automatic re-extraction on transcript change | Manual action now: a new revision is a new unit of work |

## Security

- The worker never accepts tenant ids. File access is confined to `JMOS_MEDIA_ROOT`: relative references validated by the database, resolved and checked again by the worker.
- Transcripts are untrusted evidence (docs/08 §10). The extraction can only produce proposals. Hostile text in a transcript cannot trigger any privileged action (docs/11 invariant 5).
- No transcript content goes into job input, results or errors.

## Architecture gate

**Yes.** The worker API extension is handled by ADR 0003, with the `authority:ARCHITECTURE_CHANGE` label on the TEST_SPEC PR. Nothing else changes: no entity, role or capability semantics.
