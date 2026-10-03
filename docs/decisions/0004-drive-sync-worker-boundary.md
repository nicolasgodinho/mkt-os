# ADR 0004: Drive sync runs in the worker, scoped to the leased job

- **Status:** accepted. It was decided autonomously under Nicolas's standing instruction of 2026-10-02 ("termina, sem ficar parando") and is recorded for later review.
- **Date:** 2026-10-02
- **Scope:**
  - the `worker` schema API reachable by `jmos_worker`;
  - the AI Worker's outbound access to Google APIs;
  - how Drive credentials are referenced.

  It does not change roles, capabilities or the job contract mechanism.
- **Requires:** `authority:ARCHITECTURE_CHANGE`, because it extends the exact worker-API lists in the protected guards `supabase/tests/database/000_*` and `001_*`.

## Context

docs/13 Increment 8 asks for a minimal Drive sync:
- a connection and file registry;
- manual and periodic sync;
- index hooks;
- failure states.

docs/09 already places the Drive API in the architecture (Postgres and the platform talk to Google APIs, and the Drive connector may poll on a short interval). docs/10 defines `integration_connections.credential_ref` and `file_records`.

Two questions were open:
1. Which process talks to Google?
2. How does it get credentials without putting secrets in the database or in jobs?

## Decision

1. **The AI Worker runs Drive syncs, as `drive.sync` jobs.** The web app never calls Google. That keeps the request path free of external latency and failures, and keeps one place where outbound calls happen.
2. **Same pattern as ADR 0003.** Two `SECURITY DEFINER` functions are added, executable only by `jmos_worker`:

   | Function | Purpose |
   |---|---|
   | `worker.drive_sync_for_job(job_id, worker_id, attempt)` | Returns the connection id, the folder id and the credential reference. It returns rows only while the caller holds that sync job's lease. |
   | `worker.complete_drive_sync(job_id, worker_id, attempt, result)` | Validates the snapshot again, applies it to `file_records`, records the success, completes the job and queues the next periodic sync, all **in one transaction**. It returns `completed`, `duplicate` or `lease_lost`. |

   Neither function takes a tenant id: scope derives from the leased job.

   The protected guards list the worker API exactly. With these two functions it now has the five original functions, the three from ADR 0003, and these two.
3. **Credentials are references.**
   - `credential_ref` is a short name, for example `default`. The worker resolves it to a Google service-account key file at `JMOS_DRIVE_CREDENTIALS_DIR/<workspace id>/<ref>.json`, outside the repository.
   - **Keys are bound to a workspace.** The workspace comes from the leased job, never from the connection, so no workspace can use a key kept for another, whatever reference it names.
   - **A folder feeds exactly one client.** A folder id cannot be connected twice, so no connection can mirror another client's folder into its own registry.
   - **Residual risk.** Inside a workspace, anyone with `integration.manage` can connect any folder that the workspace's service account can read. That capability is already workspace-wide (Increment 1, D1), and the agency decides what it shares with the account.
   - Keys, tokens and file contents never enter the database, jobs, logs or results.
   - The scope is read-only (`drive.readonly`), and the service account sees only the folders shared with it.
4. **Outbound access is allow-listed in the adapter.**
   - The worker calls only `https://oauth2.googleapis.com/token` and `https://www.googleapis.com/drive/v3/`, over TLS.
   - Redirects are refused.
   - Responses are size-limited and parsed as data.

   Drive file names and metadata are untrusted text. They are stored as data and never interpreted as instructions.
5. **Periodic sync uses the queue.** Completing a sync queues the next one with `run_after = now() + interval` (docs/09: the scheduler decides when, the queue guarantees execution). A failed sync stops the chain until a person requests a sync, so a broken credential does not retry forever.
6. **Without credentials, syncs fail honestly.** A missing key file fails the job with the code `drive_credentials_missing`, which is not retryable. The job center and the connection page show it. Nothing pretends to have synced.

## Consequences

- The worker becomes the only component with outbound internet access, and only to the two Google endpoints. The deployment must allow that egress for the worker host. Ollama and the worker still accept no inbound connections.
- A real Google Workspace sandbox is needed to exercise the adapter end to end. CI covers the adapter with recorded HTTP fakes, and the database side with the protected acceptance tests.
- A snapshot lists the whole tree, which is simple and self-healing. It costs more than the changes feed for large folders, so the limit is 5000 files. Moving to the changes feed with a stored cursor is the documented next step.

## Alternatives considered

- **Call Drive from the Next.js server.** Rejected: it puts external calls and credentials on the request path, and a slow Drive would block users.
- **Store OAuth refresh tokens in the database.** Rejected for v0.1: it is a new secret store, and docs/05 §5 keeps secrets out of the database. Per-user OAuth can come later with a dedicated secret store.
- **Use the changes feed from day one.** Deferred: it needs cursor management and folder-ancestry tracking. A snapshot covers the minimum.

## Migration / rollback

The migration is additive. Rollback drops the two worker functions, the two tables and their functions, and restores the eight-name lists.
