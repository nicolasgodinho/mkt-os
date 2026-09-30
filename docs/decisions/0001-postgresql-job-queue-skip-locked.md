# ADR 0001 — PostgreSQL Job Queue with SKIP LOCKED

- **Status:** proposed
- **Date:** 2026-09-30
- **Scope:** infrastructure for the job transport. The job contract (`docs/08 §5`) and the
  AI Job state machine (`docs/04`) are unchanged.
- **Requires:** `authority:ARCHITECTURE_CHANGE` (this file lives under `/docs`).

## Context

`docs/09_TECHNICAL_ARCHITECTURE.md` lists "Supabase Queues/`pgmq` for durable background jobs"
in the *recommended* v0.1 stack. `docs/08 §5` defines the **BLOCKER** job contract:
`id`, `type`, `schema_version`, `workspace_id`, `client_id?`, `idempotency_key`, input
references, `priority`, `attempts`, `max_attempts`, `lease_owner`, `lease_until`, timestamps,
`model_profile`, `pipeline_version`, status/error. `docs/04` defines the states
`QUEUED → LEASED/RUNNING → COMPLETED`, with `RETRY_WAIT`, `FAILED`, `DEAD_LETTER` and `CANCELED`.

Increment 0 needed a working queue to prove the worker foundation. The contract's explicit
lease columns, persisted status and dead-letter semantics describe a **stateful job record**.
pgmq offers a message log with visibility timeouts (`vt`, `read_ct`). With pgmq, the job
record would still be needed for status, error, fencing and the job center, so each state
change would have to be written in two places.

## Decision

Implement the queue as the `public.jobs` table itself (migration
`20260930120100_job_queue.sql`), leased with `SELECT … FOR UPDATE SKIP LOCKED`:

- `worker.claim_job` recovers expired leases, picks the next due job by priority and
  `run_after`, and leases it by setting `lease_owner`, `lease_until` and `attempts + 1`.
- Every later write (`complete_job`, `fail_job`, `extend_lease`) is fenced by
  `(lease_owner, attempt)`.
- Retryable failures back off `30s · 2^(attempt-1)`, capped at 1 h, up to `max_attempts`, then
  the job goes to `dead_letter`. Non-retryable failures go to `failed`.
- `(workspace_id, idempotency_key)` is unique. Completing a completed job is a no-op
  (`duplicate`).
- The worker reaches the queue only through the `worker.*` SQL API, as the least-privileged
  `jmos_worker` role.

pgmq is **not** used at this time.

## Invariants and evidence

| Invariant | Evidence |
|---|---|
| Durable queue | Postgres table (WAL, backups); jobs survive worker and portal restarts |
| At-least-once delivery | expired leases are redelivered — pgTAP `020_job_queue` (crash recovery) |
| Leasing | `claim_job` sets owner/lease/attempt — `020` "worker-a leases j1…", `021` |
| Lease recovery | `020` "an expired lease is recovered and re-leased…" |
| Retries | `020` retry path (`retry_scheduled`, not due before `run_after`) |
| Exponential backoff | `020` asserts 30 s, then 60 s |
| Max attempts | `020` last attempt → `dead_letter`; lease expiry on last attempt → `dead_letter` |
| Dead-letter | `020` keeps `last_error` for manual retry |
| Idempotency | unique key; `020` duplicate enqueue; `001_worker_boundary` completed work is not redelivered |
| Fencing | `020` wrong attempt / wrong worker / stale worker after reclaim → `lease_lost` |
| Concurrent workers | integration test `test_concurrent_workers_never_share_a_lease` (two workers, 20 jobs, every job `attempts = 1`), run against real Postgres in CI |
| Minimum state observability | `status`, `attempts`, `last_error`, `run_after`, timestamps; `worker_heartbeats`; JSON logs with job/trace ids |
| Least privilege | `jmos_worker` has no table privileges — `000`, `001`, and the integration test in supabase mode |

## Why not pgmq now

1. **Two stores, one truth.** The contract requires a persisted job record, so pgmq would add a
   second store. Every transition would need both writes kept consistent, which adds failure
   modes without adding a guarantee.
2. **Fencing belongs to the record.** `lease_owner` and `attempt` fencing and the explicit
   statuses map directly onto row locks and conditional updates. pgmq's `vt` and `read_ct`
   would need the same logic again on top.
3. **Surface and testability.** The table queue needs no extension, runs identically on
   Supabase and on the local PGlite fallback, and is fully covered by pgTAP.
4. **Reversibility.** The worker only calls `worker.*` functions. pgmq could later become the
   delivery mechanism behind the same functions, with no change to the worker or the contract.

## Consequences

Advantages:

- a single source of truth for job state;
- atomic, fenced transitions;
- the job center (Increment 3) can query jobs directly;
- no extension dependency.

Risks and limits:

- **Polling latency.** Idle workers poll every `JMOS_WORKER_POLL_SECONDS` (default 2 s).
  Acceptable for AI jobs; `LISTEN/NOTIFY` can reduce it later.
- **Table growth.** Finished jobs accumulate. An archival or retention policy is needed before
  the job volume becomes significant.
- **Claim contention.** Many concurrent workers compete on one index. This is far beyond the
  single-GPU topology in `docs/08 §2`.
- **No per-tenant fairness.** Ordering is priority, then due time. One tenant's backlog can delay
  others at equal priority.

## Criteria for revisiting

Reopen this decision if any of these hold:

- sustained queue volume where polling latency or claim contention measurably hurts
  client-facing jobs;
- more than a handful of concurrent workers, or more than one worker host per job class;
- a need for fan-out or pub/sub delivery that the outbox/event dispatch (Increment 3) cannot
  serve;
- `jobs` table growth that archival cannot keep bounded.

## Alternatives considered

- **pgmq (Supabase Queues) as the queue, plus a jobs table for state.** Rejected for now: it
  means dual writes and duplicated fencing (see above).
- **pgmq alone, with state in message payloads.** Rejected: it cannot represent the contract's
  persisted status, error, fencing and dead-letter semantics, and it cannot be queried by the
  job center.
- **An external broker (Redis, RabbitMQ).** Rejected: it adds infrastructure and a
  non-transactional boundary with the domain data.

## Migration / backward compatibility

None. This records what is already implemented in the Increment 0 baseline (`67b6163`).
Adopting pgmq later would be additive: new migrations and new internals for the `worker.*`
functions, with the same signatures.

## Approval

Pending: Nicolas (applies `authority:ARCHITECTURE_CHANGE` and merges).
