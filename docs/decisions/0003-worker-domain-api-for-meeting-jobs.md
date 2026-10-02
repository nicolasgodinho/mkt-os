# ADR 0003: Job-scoped worker domain API for meeting jobs

- **Status:** accepted. It was decided autonomously under Nicolas's standing instruction of 2026-10-02 ("termina, sem ficar parando") and is recorded for later review.
- **Date:** 2026-10-02
- **Scope:** the `worker` schema API reachable by `jmos_worker`. It does not change roles, capabilities or the job contract.
- **Requires:** `authority:ARCHITECTURE_CHANGE`, because this PR extends the exact worker-API lists in the protected guards `supabase/tests/database/000_*` and `001_*`.

## Context

ADR 0001 left `jmos_worker` with exactly five functions: `claim_job`, `complete_job`, `extend_lease`, `fail_job` and `heartbeat`. It also set one rule for later growth: "every worker read of domain data must go through `worker.*` functions scoped to the **leased job's** workspace/client and lease... Never add a worker function that queries across tenants or accepts a tenant id that is not the leased job's".

Increment 4 needs two things from the worker:
- it must **read** meeting content: the transcript to extract from, and the recording reference to transcribe;
- it must **write** domain results: proposals and a transcript revision.

docs/11 invariant 6 requires that a duplicate delivery creates no duplicate side effects.

## Decision

Add three `SECURITY DEFINER` functions to the `worker` schema, executable only by `jmos_worker`:

| Function | Purpose |
|---|---|
| `worker.meeting_for_job(job_id, worker_id, attempt)` | Returns the meeting title, recording reference and the transcript revision named in the job input. It returns rows only while the caller holds that job's lease, for meeting job types only, and only when the meeting belongs to the job's client. |
| `worker.complete_meeting_extraction(job_id, worker_id, attempt, result)` | Validates the result shape again, inserts `meeting_proposals` and completes the job **in one transaction**. |
| `worker.complete_meeting_transcription(job_id, worker_id, attempt, result)` | Same pattern for a new transcript revision. |

The two `complete_*` functions return `completed`, `duplicate` (the job is already completed; nothing is written) or `lease_lost` (the caller is fenced out; nothing is written).

**Rules these functions follow:**
- None of them takes a workspace, client or meeting id. Scope always derives from the leased job. A protected acceptance test checks that no worker function has such a parameter.
- They write only proposals and transcripts, never knowledge, rules or approvals. Promotion stays a human, capability-checked step.
- The internal helpers they use (`worker.lease_for_completion`, `worker.finish_job`) are not executable by any API role or by `jmos_worker`.

The protected guards keep listing the worker API **exactly**: the five original functions plus these three. Any further worker function needs another ADR.

## Consequences

- The worker can run domain pipelines without table privileges, `service_role` or tenant ids.
- Exactly-once results come from writing domain rows and the completion in the same transaction. This is cheaper than an outbox for this case. An outbox (docs/09) is still due when a second asynchronous consumer appears.
- Each new domain pipeline adds functions in the same pattern (read fenced by the lease; complete with the domain writes) and needs its own ADR addition.

## Alternatives considered

- **Give `jmos_worker` SELECT/INSERT on meeting tables.** Rejected: it breaks least privilege, and RLS cannot scope by lease.
- **Return results through `complete_job` and apply them with a trigger or a separate consumer.** Rejected: it adds a second step that can fail between completion and domain write, so it is not atomic.
- **Pass the transcript in the job input.** Rejected: job input must hold references, not content (docs/08 §5). It would also put client content in a jsonb column with broader readership (the job center).

## Migration / rollback

The migration is additive. Rollback drops the three functions and restores the five-name lists.
