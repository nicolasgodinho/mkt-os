# Increment 3: AI queue/worker (protected acceptance contract)

**Authority:** `TEST_SPEC`. Builders must not edit these files (docs/11 "Protected paths").

**Spec anchors:**
- docs/13 Increment 3: durable queue contract, local Python worker, model adapter, job center and status, idempotency tests.
- docs/08 §2–§5, §7, §10.
- docs/04 "AI Job".
- docs/15 "AI worker health": online/offline, active model profile, running, queued and failed counts, last successful job, dead-letter jobs, cancel and retry of safe jobs.
- docs/03 journey G (the worker is offline).
- docs/11 invariants 6 (job idempotency) and 9 (portal boundary).
- ADR 0001: Postgres table queue, `worker.*` API, fencing by `(lease_owner, attempt)`.

## Decisions frozen here

These were made by the agent under Nicolas's standing instruction to proceed autonomously (2026-10-02). They are recorded in ExecPlan 0003.

1. **Capability.** Job center actions (request, cancel, retry) require **`workspace.manage`**. No new capability is added; the capability contract is unchanged. Reading jobs and the summary keeps the Increment 0 rule: internal access (`client.view`), never client roles.
2. **System jobs only.** `request_system_job` can only enqueue an allow-listed set: `system.healthcheck` v1 and `ai.model_check` v1. Domain jobs, such as `meeting.extract` in Increment 4, are enqueued by their own domain functions, each checked with its own capability.
3. **Cancel.** Only `queued` and `retry_wait` jobs can be canceled. A `running` job keeps its lease. Cancellation is never forced on a worker.
4. **Retry.** Allowed for `failed`, `dead_letter` and `canceled` jobs.
   - **Attempt numbers are never reset.** They are the fencing token, so a stale worker from an earlier attempt can never complete the retried job.
   - The retry grants at least one more attempt.
5. **AI model check.** `ai.model_check` jobs declare the model profile `reasoning` (docs/08 §4). The prompt is fixed by the pipeline; the job input is empty, so no user text reaches the model through it.

## Database API frozen by these tests

Everything below is in schema `public`, executable by `authenticated` only. The error contract and the order of checks are the same as in Increment 2:
1. **Target** not visible: `P0002 'not found'`.
2. **Capability** missing: `42501 'permission denied'`.
3. **Argument or state** invalid: `22023`.

A job is visible exactly when the `jobs` row-level-security policy shows it to the caller.

| Function | Rule |
|---|---|
| `request_system_job(p_workspace_id uuid, p_type text, p_idempotency_key text) → uuid` | `workspace.manage`; type allow-listed (22023 otherwise); key non-blank, at most 200 chars. Creates a workspace job (`client_id` null, `created_by` = caller, `pipeline_version` set). Idempotent: the same key returns the same job, whatever its status; the same key for another type raises 23505. Audited. |
| `cancel_job(p_job_id uuid) → void` | `workspace.manage` in the job's workspace; `queued`/`retry_wait` → `canceled` (terminal). Audited. |
| `retry_job(p_job_id uuid) → void` | `workspace.manage`; `failed`/`dead_letter`/`canceled` → `queued` (`finished_at` cleared, attempts kept, `max_attempts > attempts`). Audited. |
| `job_center_summary(p_workspace_id uuid)` | One row, with integer columns `queued, running, stalled, retry_wait, completed, failed, dead_letter, canceled` and `last_completed_at`. `running` includes `stalled` (running with an expired lease). No rows without internal access to the workspace. |

**Additional invariants**
- Tables stay read-only for API roles.
- `jmos_worker` keeps only the `worker.*` API. The Increment 1 tests cover this generically.

**TypeScript (`320`).** `packages/core` registers `system.healthcheck.v1` and `ai.model_check.v1`.
- The model-check input is the empty object (strict).
- The output is strict, with the fields `model_profile`, `model` (non-empty), `latency_ms` (integer, 0 or more) and `ok`.

## Fixture

- **Workspaces and clients:** Workspace A {A1}, Workspace B {B1}. The ids are the same as in Increments 1 and 2.
- **Users:**
  - `a_admin`, `a_strategist` and `a_contributor` (no grants) in A;
  - `b_admin` in B;
  - `a1_cadmin` (client admin of A1).
- **Jobs:**
  - Created with the privileged `app.enqueue_job` and driven through `worker.*`, the way the worker does it.
  - Every job type is unique per scenario, so `claim_job` only leases the intended job.

## Deferred coverage

| Topic | Arrives with |
|---|---|
| Domain job side effects in the completion transaction (`meeting.extract` → proposed knowledge, exactly once) | Increment 4 |
| Realtime status push | When the UI needs it; the job center reads on request |
| Retention or archival of finished jobs | Operations (ADR 0001 "Table growth") |
| Per-tenant fairness | ADR 0001 revisit criteria |
