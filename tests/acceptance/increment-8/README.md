# Increment 8: Drive sync minimum (protected acceptance contract)

**Authority:** `TEST_SPEC`. Builders must not edit these files (docs/11 "Protected paths").

**Spec anchors:**
- docs/13 Increment 8: connection and file registry, manual and periodic sync, index/re-index hooks, failure states. Also step 3 of the demo loop: link a client Drive folder.
- docs/02 Asset and Files: bytes stay in Drive, the database keeps semantics and Drive identifiers.
- docs/09 "Drive connector" and "Scheduler vs Queue".
- docs/10 `integration_connections` and `file_records`.
- docs/05 §5: secrets never enter the repository or the database.
- docs/11 invariant 6 (job idempotency) and invariant 9 (portal boundary).
- ADR 0001, 0003 and 0004: the worker API.

## Decisions frozen here

They were taken autonomously under Nicolas's standing instruction of 2026-10-02 and are recorded in ExecPlan 0008 and ADR 0004.

1. **Connection.** Each client has at most one Google Drive connection, created with `integration.manage`. It names:
   - a folder id in Drive's id format;
   - a **credential reference**: a short name (`^[a-z0-9_]{1,40}$`) that the worker resolves from its own environment, inside the directory of the job's workspace (ADR 0004). The secret itself never enters the database or a job.

   A folder can be connected to only one client.
   - a sync interval between 15 and 1440 minutes (default 60).

   Connecting queues the first sync right away.
2. **Sync is a job.** Each sync is a `drive.sync` v1 job whose input is only `{connection_id}`. A connection has at most one open sync job (queued, waiting to retry, or running).
   - `request_drive_sync` returns the open job and brings its time forward to now.
   - If the last sync failed, `request_drive_sync` queues that same job again.
   - Otherwise it creates a new job.
3. **Periodic sync.** Completing a sync queues the next one at `now() + interval`, through the queue's `run_after`, unless the connection is paused. Pausing cancels the open queued sync. Resuming queues one right away.
4. **Snapshot semantics.** The worker returns metadata for every file under the folder tree, never file contents, and at most 5000 files. The database applies the snapshot in the completion transaction (exactly once):

   | Situation | Result |
   |---|---|
   | New file | `synced`, index `pending` |
   | Same revision | unchanged |
   | New revision, or the file comes back | `synced`, index `pending` |
   | Missing from the snapshot | `removed`, index `skipped` |

   A redelivered completion returns `duplicate`, and a fenced-out worker gets `lease_lost`. Neither writes anything.
5. **Index hooks.** `pending` is the hook state for the future indexing pipeline. `request_file_reindex` (`integration.manage`) puts a file back to `pending`. A removed file cannot be re-indexed.
6. **Failure states.** A failed sync keeps its status and error code on the job (the job center shows it), and nothing else is scheduled until someone requests a sync. The connection records `last_success_at`.
7. **Visibility.** Internal staff with access to the client read its connection and file records. Client members see nothing of the Drive registry in v0.1; portal Files come later. Nobody writes these tables directly.
8. **Worker boundary (ADR 0004).**
   - `worker.drive_sync_for_job(p_job_id, p_worker_id, p_attempt)` returns `(connection_id, root_folder_id, credential_ref)` only while the caller holds that sync job's lease.
   - `worker.complete_drive_sync(p_job_id, p_worker_id, p_attempt, p_result)` applies the snapshot and completes the job. It returns `completed`, `duplicate` or `lease_lost`.

   Neither function takes a tenant id, and neither is callable by API roles.

## Database API frozen by these tests

The public functions are executable by `authenticated` only. Errors follow the same contract as before: P0002 when the target is not visible, then 42501, then 22023.

| Function | Rule |
|---|---|
| `connect_drive_folder(p_client_id, p_root_folder_id text, p_credential_ref text default 'default', p_sync_interval_minutes integer default 60) → uuid` | Decision 1. |
| `set_drive_connection_status(p_connection_id, p_status text)` | `active` or `paused` (decision 3). |
| `request_drive_sync(p_connection_id) → uuid` | Decision 2. Refused while the connection is paused. |
| `request_file_reindex(p_file_id)` | Decision 5. |

**22023 messages:** `invalid drive folder id`, `invalid credential reference`, `invalid sync interval`, `this client already has a drive connection`, `unknown connection status`, `this drive connection is paused`, `removed files cannot be indexed`, `invalid drive sync result`. The builder may add messages for rules these tests do not cover, for example one folder per client.

**Job contract (`830_drive_contracts.test.ts`):**
- `drive.sync` v1 input: `{connection_id}` (strict).
- Output: `{files: [{drive_file_id, name, mime_type, revision, modified_at?, size_bytes?, md5_checksum?}]}`. It is strict and holds at most 5000 files.

**Columns read by the tests:**
- `integration_connections`: `id, client_id, provider, status, root_folder_id, credential_ref, sync_interval_minutes, last_success_at`.
- `file_records`: `id, client_id, connection_id, drive_file_id, name, drive_revision, sync_status, index_status`.
- `jobs`: `id, type, schema_version, client_id, input, status, run_after, last_error`.

## Fixture

- **Workspaces and clients:** Workspace A {A1, A2} and Workspace B {B1}, with the same ids as earlier increments.
- **Users:**
  - `a_admin`, who has `integration.manage` as admin;
  - `a_strategist`: client access without `integration.manage`;
  - `b_admin`;
  - `a1_cadmin`: a client admin of A1.
- **Setup:** A1 is connected by `a_admin`. The worker side runs as the privileged owner, as in Increment 4.

## Mutation proof

Run against a throwaway prototype.
- **Satisfiable:** 56 of 56 SQL assertions pass on the prototype.
- **Caught, 10 of 11:**
  - clients reading file records;
  - the worker context without a lease check;
  - never marking files removed;
  - no periodic schedule;
  - a paused connection still scheduling;
  - manual syncs piling up jobs;
  - pausing that keeps the open job;
  - re-indexing removed files;
  - a credential reference accepting free text;
  - no retry of a failed sync.
- **Equivalent, 1 of 11:** "a new revision keeps its index status" cannot be observed in this increment. Until indexing exists, a synced file is always `pending`.

## Deferred coverage

| Topic | Arrives with |
|---|---|
| Indexing itself (`indexing`, `indexed`, `failed`) | The RAG/indexing increment |
| Drive changes feed and push notifications (cursor) | When snapshots get too large (docs/09) |
| Portal Files, links between file records and content or assets | Later portal and asset work |
| Several connections per client, other providers | When needed |
