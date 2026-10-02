# Increment 4: Meeting intelligence (protected acceptance contract)

**Authority:** `TEST_SPEC`. Builders must not edit these files (docs/11 "Protected paths").

This PR also extends the exact worker-API lists in the protected guards `supabase/tests/database/000_*` and `001_*` (`authority:ARCHITECTURE_CHANGE`; see ADR 0003).

**Spec anchors:**
- docs/13 Increment 4: Source file reference, transcription adapter, extraction schema, review screen, promotion to knowledge.
- docs/02 "Meeting" and "Source".
- docs/03 journey D: no permanent Rule or Fact is silently created from model inference.
- docs/07 §11: Meeting Intelligence Review.
- docs/08 §5, §7 and §10.
- docs/10 `meetings`.
- docs/11 invariants 4 (knowledge safety), 5 (untrusted content), 6 (job idempotency) and 9.
- ADR 0001: the worker API is scoped to the leased job.

## Decisions frozen here

These were made autonomously under Nicolas's standing instruction (2026-10-02) and are recorded in ExecPlan 0004 and ADR 0003.

1. **Meeting and Source.** Every meeting owns a `FIRST_PARTY` Source of type `meeting`. Anything extracted from the meeting cites that Source.
2. **Proposals, not knowledge.** Model output only becomes `meeting_proposals`. Accepting a proposal (`knowledge.propose`) creates **proposed** knowledge through the Increment 2 API. Approval (`knowledge.approve`) and activation (`rule.activate`) stay separate steps. The model never creates or activates anything.
3. **Exactly-once results.** The worker writes proposals and transcripts only through job-scoped `worker.*` functions, fenced by the lease. They are written in the same transaction as the completion; a duplicate delivery returns `duplicate` and writes nothing.
4. **One unit of work.** Extraction is idempotent per transcript revision. Transcription is idempotent per recording reference.
5. **Recording reference.** Before Drive sync (Increment 8), the recording is a relative path under the worker's media root:
   - every segment starts with a letter or digit;
   - so `..`, absolute paths and hidden files are impossible.
6. **Tasks.** Task and question proposals cannot be promoted until the Task entity exists (v0.2). They can be rejected.
7. **Internal only.** Meetings, transcripts and proposals are internal-only, like the Client Brain (Increment 2 decision 3).

## Database API frozen by these tests

**Public functions.** In schema `public`, `authenticated` only. Same error contract and check order as Increments 2 and 3:
- the client or item is not visible: P0002;
- the capability is missing: 42501;
- the argument or state is invalid: 22023.

All of them require `knowledge.propose`.

| Function | Notes |
|---|---|
| `create_meeting(p_client_id, p_title, p_starts_at, p_ends_at default null, p_participants jsonb default '[]', p_recording_ref text default null) → uuid` | Creates the meeting and its `meeting` Source. |
| `save_meeting_transcript(p_meeting_id, p_text) → integer` | Returns the new revision, starting at 1. |
| `request_meeting_extraction(p_meeting_id) → uuid` | Job `meeting.extract` v1, input `{meeting_id, transcript_revision}`, profile `reasoning`. |
| `request_meeting_transcription(p_meeting_id) → uuid` | Job `meeting.transcribe` v1, input `{meeting_id}`, profile `transcription`. |
| `accept_meeting_proposal(p_proposal_id, p_statement default null) → uuid` | Returns the id of the created proposed fact, decision, insight or rule. |
| `reject_meeting_proposal(p_proposal_id) → void` | |

**Worker functions.** In schema `worker`, for `jmos_worker` only. They take no tenant or meeting id; the scope comes from the leased job.

| Function | Notes |
|---|---|
| `meeting_for_job(p_job_id, p_worker_id, p_attempt)` | Returns `meeting_id, title, recording_ref, transcript, transcript_revision`. Returns no rows unless the caller holds that lease. |
| `complete_meeting_extraction(p_job_id, p_worker_id, p_attempt, p_result jsonb) → text` | Returns `completed`, `duplicate` or `lease_lost`. |
| `complete_meeting_transcription(...)` | Same contract, for transcription jobs. |

**Meeting statuses:** `new → transcribing → transcribed → extracting → in_review`.

**Columns read by the tests:**
- `meetings`: `client_id`, `processing_status`, `transcript_source_id`;
- `meeting_transcripts`: `meeting_id`, `revision`, `text`, `origin` (`manual` or `transcription`);
- `meeting_proposals`: `meeting_id`, `client_id`, `kind`, `statement`, `status`, `transcript_revision`, `rule_type`, `subject`, `accepted_item_id`.

**Job contracts (`430`, TypeScript).**
- `meeting.extract.v1` takes `{meeting_id: uuid, transcript_revision: int}` (strict). It returns `{proposals: [...]}`: at most 100 items, each `{kind, statement, confidence?, evidence_quote?, time_ref?, rule_type? (required for rules), subject?}`.
- `meeting.transcribe.v1` takes `{meeting_id}` (strict). It returns `{text, language?, segments: [{start_ms, end_ms, text}]}`.

## Fixture

- Workspace A {A1, A2}, Workspace B {B1}, with the same ids as in earlier increments.
- Users: `a_admin`, `a_strategist`, `a_creative` (no `knowledge.propose`) and `a_contributor` in A; `b_admin`; `a1_cadmin` and `a1_approver` on A1.
- Meetings are created through the API in the header.
- The worker side calls `worker.*` as the owner, exactly like `jmos_worker`.

## Deferred coverage

| Topic | Arrives with |
|---|---|
| Drive file references for recordings and documents | Increment 8 (FileRecord) |
| Promoting tasks and questions | v0.2 (Project/Deliverable/Task) |
| Semantic or near-duplicate proposal detection | Later (human-confirmed) |
| `meeting.completed` domain event | First asynchronous consumer |
