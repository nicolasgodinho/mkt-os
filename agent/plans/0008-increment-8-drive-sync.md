# ExecPlan 0008 — Increment 8: Drive sync minimum

**Status:** approved under Nicolas's standing instruction (2026-10-02). This plan runs autonomously. Its decisions are recorded here, in the TEST_SPEC README and in ADR 0004.

**Spec anchor:** docs/13 Increment 8: connection and file registry, manual and periodic sync, index/re-index hooks, failure states. Also demo-loop step 3: link a client Drive folder.

**Contract:** `tests/acceptance/increment-8/` and ADR 0004 (PR nicolasgodinho/mkt-os#28, `authority:TEST_SPEC` + `authority:ARCHITECTURE_CHANGE`). Where the tests and this plan disagree, the tests win.

## Goal

Give every client a linked Drive folder whose files the platform knows about. The database keeps metadata and sync or index state; the bytes stay in Drive (docs/02). This is the foundation for RAG indexing, assets and portal files.

## Decisions

The README and ADR 0004 freeze these decisions:
1. **One connection per client** (`integration.manage`). It names a folder id, a credential *reference* (never a secret) and an interval of 15 to 1440 minutes.
2. **Sync is a `drive.sync` v1 job**, at most one open per connection.
   - A manual request brings that job forward, or retries the last failed one.
   - Completion queues the next sync after the interval, unless the connection is paused.
3. **Snapshot semantics,** applied exactly once in the completion transaction: new, changed and reappearing files become index `pending`; missing files become `removed`.
4. **Re-index hook:** `request_file_reindex` sets index `pending`.
5. **Failure states** live on the sync job: status and error code.
6. **Visibility:** the registry is internal only.
7. **Worker boundary:** two job-scoped worker functions (ADR 0004), the same pattern as ADR 0003.

Builder-level decisions (not frozen by tests):
- **Credentials.** A service account per credential reference: `$JMOS_DRIVE_CREDENTIALS_DIR/<ref>.json`, read-only scope. The JWT is signed with `cryptography` (new pinned dependency). There is no OAuth user flow in v0.1.
- **Egress.** Only the Google token endpoint and the Drive v3 API. No redirects, no proxies, and bounded responses.
- **Always advertised.** The handler is always advertised, so a worker without credentials fails syncs visibly (`drive_credentials_missing`) instead of leaving them queued forever.
- **UI placement.** The page is `/w/[ws]/clients/[id]/drive`, linked from the client overview, until the client-context navigation exists. The derived sync state comes from the latest job, and failure codes are explained in pt-BR.

## In scope

- **Migration `20261002220000_drive_sync.sql`:** tables, functions, worker functions and RLS.
- **Guards:** the protected guards 000/001 list the worker API.
- **Builder pgTAP `100_drive_sync`:** audit names, hardening, table constraints, helper privileges.
- **Contract:** `drive.sync` v1 in `packages/core`, plus the generated worker schema.
- **Worker:**
  - `drive.py`: credentials, JWT, transport and snapshot;
  - the handler, configuration and wiring;
  - unit tests with an in-memory Drive fake;
  - a Postgres integration test of the full job.
- **Web:**
  - the Drive page: connect, state, sync now, pause or resume, files, re-index;
  - the overview card;
  - unit tests (derived state, folder links, error drift).
- **Seed:** a connected folder for Cliente Demo A, with files and no queued sync.
- **E2E:** the admin flow (files, sync now, re-index, pause and resume); read-only staff; clients get a 404 and no API access.

## Non-goals (deferred)

| Item | Destination |
|---|---|
| Indexing / RAG over file contents | RAG increment |
| Drive changes feed or push notifications with a cursor | When snapshots get too large |
| Per-user OAuth and a secret store | Later (ADR 0004 alternatives) |
| Portal Files; links to content and assets | Later portal and asset work |
| A real Google sandbox run in CI | When a test Workspace exists. The adapter is covered with fakes today. |

## Security

- **Secrets.** They never enter the database, jobs, logs or results. Key files live outside the repository on the worker host.
- **Worker functions.** They take no tenant id and are fenced by the lease. Tables have no write grants, and API roles cannot call the helpers.
- **Untrusted metadata.** Drive names and metadata are stored and rendered as text only.

## Architecture gate

**Yes, handled conservatively.** The worker's outbound access to Google and two new worker functions form a new trust boundary. They are recorded in ADR 0004 under `authority:ARCHITECTURE_CHANGE`, following the docs/09 deployment shape, which already names Google APIs. There are no role or capability changes.
