# ExecPlan 0000 — Increment 0: Repository / quality harness (Foundation)

Status: implemented (see "Outcome" at the end)
Spec anchor: `docs/13_MVP_BUILD_PLAN.md` → Increment 0.

## Goal

Make the repository ready for later agents to build modules on their own without breaking
the architecture. After this plan:

- one command (`pnpm verify`) runs every quality gate;
- the tenancy kernel is protected by RLS from the first migration, and tests prove it;
- the AI Worker skeleton can lease jobs safely (at-least-once delivery, idempotent writes);
- CI reproduces the same gates and guards protected paths.

## User value

The product has no user-facing value yet. The value goes to builders: every later
increment starts from a harness where RLS, tenancy and job-safety regressions fail CI.

## In scope

Spec Increment 0 items:

- monorepo skeleton (pnpm workspaces): `apps/web`, `apps/ai-worker`, `packages/core`, `packages/ui`;
- formatting, lint and type checking (Prettier, ESLint with strict typescript-eslint, `tsc`; ruff and mypy --strict for Python);
- test harness: Vitest (unit), pgTAP (DB/RLS), pytest (worker unit + integration), Playwright (E2E), acceptance-test runners;
- local Supabase (`supabase/config.toml`, migrations, seed) plus a no-Docker PGlite fallback;
- CI (GitHub Actions) running the same `pnpm verify` against real Supabase;
- protected acceptance-test convention (CODEOWNERS plus a CI guard for protected paths and append-only migrations).

The user's run brief asks for more than the spec lists. These items are needed to prove the
harness end to end:

1. **Tenancy kernel schema** (`workspaces`, `users`, `workspace_memberships`, `clients`,
   `client_memberships`) with RLS and negative tests. The brief requires tenant isolation
   proven by tests, and that is impossible without tenant tables. Only the persistence layer
   and read policies are built here. See Non-goals for what stays in Increment 1.
2. **Job queue foundation** (`jobs`, `worker_heartbeats`, a narrow `worker` SQL API) and the
   **AI Worker skeleton**: process, config, logging, lease loop, retries, graceful shutdown,
   heartbeat. The only real job type is the diagnostic `system.healthcheck` v1. It exists to
   prove the enqueue → lease → execute → complete path. No AI pipeline is implemented.

## Non-goals (explicitly left to later increments)

- Auth UX (sign-in, session middleware), internal/client shells wired to identity, membership
  management services, capability resolution service, and audit of membership changes.
  Owner: **Increment 1**.
- Contributor → client assignment model. This is currently **fail-closed**: contributors see no client data.
  Owner: Increment 1.
- Protected cross-tenant acceptance tests in `/tests/acceptance`. These need `TEST_SPEC` authority,
  which this run does not have. Only the runners and the convention exist. Owner: Increment 1 Test Designer.
- Job center UI, manual retry/cancel, user-facing enqueue RPC with capability checks, model
  adapters (Ollama, faster-whisper), and a pgmq transport decision. Owner: **Increment 3**.
- Domain events/outbox, audit_logs, and every Strategy/Knowledge/Content/Collaboration table.
  Outbox is CORE in `09`, but it is not listed in Increment 0. It should land with the first
  increment that emits a domain event (Increment 2 knowledge promotion / `rule.activated`).
- Generated Supabase TypeScript DB types. The web app does not query the DB yet. Type
  generation (`pnpm db:types`) is scripted, and the typed client lands with Increment 1.

## Relevant authoritative docs

00 (invariants, BLOCKERs), 01 (roles/capabilities), 02 §1/§7 (Identity, shared base fields),
04 (AI Job state machine), 05 §1/§3/§5 (isolation, trust boundary, secrets), 06 (navigation
IA for shells), 07 (UI system patterns), 08 §2/§5 (worker topology, job contract), 09 (stack,
module boundaries, observability), 10 (Identity + Platform tables, RLS principle), 11 (test
layers, CI command contract, protected paths), 12 (protocol), 13 (increments), 15 (worker health).

## Domain entities affected

Identity: Workspace, User (profile), WorkspaceMembership, Client, ClientMembership.
Platform: Job, worker heartbeat (health, see `15` "AI worker health").

## State transitions

AI Job (`04`): `queued → running → completed`; failure paths `running → retry_wait → (queued) → running`,
`running → failed`, `running → dead_letter`, `queued|retry_wait → canceled` (reserved for Increment 3's job center).

- `LEASED/RUNNING` is one persisted status, `running`, with lease columns set.
- `retry_wait → queued` happens atomically inside `claim_job`: a `retry_wait` row whose
  `run_after` has passed can be claimed. No separate sweeper is needed.
- An expired lease (`running` with `lease_until < now()`) is recovered by the next `claim_job`
  call. It goes back to `queued`, or to `dead_letter` if attempts are exhausted.
- `failed` = permanent, non-retryable error. `dead_letter` = retries or leases exhausted. Both
  wait for a manual retry (Increment 3).
- Fencing: every worker write is keyed by `(job_id, lease_owner, attempt)`. A stale worker whose
  lease was reclaimed gets `lease_lost` and cannot overwrite the new attempt.
- Idempotency: `(workspace_id, idempotency_key)` is unique, so enqueueing twice returns the same
  job. Completing twice is a no-op that returns `duplicate`.

## Permissions/security

- RLS is enabled on every `public` table. A generic pgTAP guard fails if any table is added without RLS.
- No `USING (true)` / `WITH CHECK (true)` policies. A generic guard enforces this.
- `anon` has no privileges on any `public` table. Grants are explicit per table, independent of
  Supabase default privileges.
- Read policies only in this increment. Every write to tenancy tables is denied to
  `authenticated` because it goes through privileged services (Increment 1).
- Access helpers live in the non-exposed schema `app`. They are `SECURITY DEFINER` with an empty
  `search_path`:
  - `app.is_workspace_member(ws)` → active internal membership.
  - `app.has_internal_client_access(client)` → active internal membership in the client's
    workspace with role ≠ `contributor` (fail-closed until Increment 1 defines assignment).
  - `app.is_client_member(client)` → active client membership.
- Jobs are internal-only (`05` visibility boundary, `11` invariant 9). Client roles never see
  jobs or worker health.
- The worker uses a dedicated DB role `jmos_worker`: no table privileges, `EXECUTE` only on
  `worker.*` functions (schema not exposed through PostgREST), no `BYPASSRLS`. It is not
  `service_role`. The worker makes only outbound connections and never listens on a port
  (`05`, `08 §2`).
- Secrets: `.env*` files are git-ignored. `.env.example` holds local-only placeholders. The worker's
  local password is set only in `supabase/seed.sql` (local dev database). In production an operator
  sets it through secret storage.
- `app.enqueue_job` is not callable by `anon`/`authenticated` yet. Increment 3 exposes a
  capability-checked enqueue RPC.

## Database/migrations

- `supabase/migrations/20260930120000_tenancy_kernel.sql`
- `supabase/migrations/20260930120100_job_queue.sql`
- `supabase/seed.sql` holds minimal dev data: one workspace, two clients, internal and client users,
  memberships, and the local worker login.
- Migrations are additive and append-only. CI rejects modification or deletion of an existing migration file.
- Postgres major version 17 (Supabase local). The PGlite fallback runs PG 18. Avoid version-specific syntax.

## API/events/jobs/contracts

- `packages/core` holds the source of truth for job-type payload contracts (zod):
  `system.healthcheck` v1 input/output, plus the deterministic idempotency-key helper.
- `pnpm contracts:generate` writes JSON Schema into `apps/ai-worker/src/jmos_worker/contract_schemas/`.
  The worker validates input and output against these files. `pnpm contracts:check` fails if they are stale.
- The DB is the source of truth for persisted shapes: enums and columns. Generated TS DB types arrive in Increment 1.
- No domain events in this increment (see Non-goals).

## UI/screens

- `packages/ui`: design tokens (CSS variables, light/dark), `cn`, `Button`, and the spec primitives
  needed by the shells: `AppShell`, `Sidebar`, `PageHeader`, `StatusBadge`, `EmptyState`.
- `apps/web`: App Router with route groups `(internal)` (desktop-first sidebar with the `06` global
  navigation) and `portal` (mobile-first with the `06` portal navigation). Each has one placeholder
  page that proves the layout. Navigation entries for modules that do not exist yet render as
  disabled, labelled "em breve", so nothing links to a fake page.
- `/api/health` is the web liveness check. It never depends on the AI Worker.

## Failure states

- Worker offline: jobs stay `queued` and the web app is unaffected (E2E runs without a worker).
- Worker crash mid-job: the lease expires and the job is re-leased (at-least-once) or dead-lettered.
- Handler exception: retryable → `retry_wait` with exponential backoff; non-retryable → `failed`.
- Invalid input/output payload: non-retryable `failed` with `code = invalid_input|invalid_output`.
- Unknown job type: the worker claims only the types it registers, so unknown types stay queued.
- DB unavailable for the worker: the loop logs the error, backs off and retries, and does not exit.

## Acceptance criteria

1. `pnpm install && pnpm setup:py && pnpm verify` passes on a clean checkout (PGlite mode locally)
   and in CI (strict Supabase mode).
2. Migrations apply to an empty database; seed applies after them.
3. pgTAP proves: cross-workspace and cross-client reads return nothing (guessed UUIDs included);
   client roles never see jobs; `anon`, outsiders and contributors see nothing; `authenticated` cannot
   write tenancy tables or call worker functions; `jmos_worker` cannot read tables.
4. pgTAP proves the job state machine: idempotent enqueue, lease, fencing, retry/backoff,
   dead-letter, lease-expiry recovery, idempotent completion.
5. The worker processes a `system.healthcheck` job end to end against a real Postgres wire
   connection (integration test), including graceful shutdown.
6. E2E: the internal shell (desktop) and portal shell (mobile) render, and health responds with no worker running.
7. CI workflow exists with the same gates, and a PR guard covers protected paths and migrations.

## Test plan

| Layer | Tool | Location |
|---|---|---|
| Format | Prettier, ruff format | repo |
| Lint | ESLint (typescript-eslint strict-type-checked, next), ruff | repo |
| Types | `tsc --noEmit` per package, mypy --strict | repo |
| Contracts | generated JSON Schema drift check | `packages/core` |
| Unit | Vitest; pytest (`not integration`) | `packages/*/src/**/*.test.ts`, `apps/ai-worker/tests/unit` |
| DB/RLS | pgTAP via `scripts/db` runner (PGlite or real Supabase) | `supabase/tests/database` |
| Integration | pytest `-m integration` against Postgres wire | `apps/ai-worker/tests/integration` |
| E2E | Playwright | `tests/e2e` |
| Acceptance (protected) | Vitest and pgTAP runners, include globs only | `tests/acceptance` (empty; needs TEST_SPEC) |

## Observability/audit

- Worker: JSON-lines structured logs with `trace_id`, `workspace_id`, `client_id`, `job_id`,
  `job_type`, `attempt`, `worker_id`. Errors are persisted on the job (`last_error`) without secrets or payloads.
- Worker heartbeat row: status, version, supported job types, last_seen_at (`15` AI worker health).
- Audit log: not in this increment (no audited actions exist yet).

## Rollout/rollback notes

Local and CI only. There is no deployment in this increment. Both migrations are additive on an
empty schema. Rolling back means a DB reset (local/CI only).

## Assumptions / decisions (reversible implementation choices)

- **D1 — Local DB fallback.** This machine has no Docker, so `supabase start` cannot run.
  `scripts/db` runs the real migrations, seed and pgTAP files either against real Supabase
  (`JMOS_DB_MODE=supabase`, required in CI) or against PGlite (Postgres WASM) with a small
  Supabase-compat bootstrap (`anon`/`authenticated`/`service_role` roles, `auth.uid()`,
  minimal `auth.users`, Supabase default privileges). Real Supabase is the authoritative gate.
  PGlite is a developer convenience and `verify` labels it clearly.
- **D2 — Job transport.** `09` recommends Supabase Queues/pgmq. The BLOCKER job contract
  (`08 §5`: lease_owner/lease_until/attempts/idempotency_key/status) is implemented as a
  Postgres table leased with `FOR UPDATE SKIP LOCKED`. The table is the contract and the queue at
  once, with no dual-write between pgmq and a status table. The worker only talks to `worker.*`
  SQL functions, so pgmq can become the transport later without changing the worker or the
  contract. Flagged for confirmation in Increment 3 (non-blocking).
- **D3 — Job type naming.** `type` is a dotted lowercase name (`meeting.extract`) and
  `schema_version` is an integer. The pair maps to the `08 §7` names (`meeting.extract.v1`).
- **D4 — Priority.** 0–100, higher first, default 50.
- **D5 — Retry backoff.** Computed in SQL: `least(30s · 2^(attempt-1), 1h)`.
  Default `max_attempts = 3`.
- **D6 — Roles.** `workspace_role`: `admin` (persona Owner/Admin), `account`, `strategist`,
  `creative`, `analyst`, `contributor`. `client_role`: `client_admin`, `approver`,
  `collaborator`, `viewer`. `capability` enum = the 20 capabilities of `01`. Role → capability
  defaults are Increment 1.
- **D7 — Statuses.** `workspace_status` / `client_status` = `active|archived` (soft delete first,
  `05 §7`). `membership_status` = `invited|active|revoked`. Values can be added later
  (additive enum change) for lifecycle states such as `closing`.
- **D8 — Internal visibility.** Non-contributor internal members see every client in their workspace
  (`01`: Owner/Admin sees all; the other internal roles work across clients).
  Contributors see none until Increment 1 adds explicit assignment (fail-closed).
- **D9 — UI language.** Product copy is pt-BR. Code identifiers and docs are English.
- **D10 — Packages.** Only `packages/core` and `packages/ui` are created. The other `09` module
  packages are created by the increment that first needs them (no empty packages).
- **D11 — Toolchain pins.** TypeScript 5.9 (typescript-eslint does not support TS 7 yet).
  ESLint 10 with typescript-eslint strict-type-checked, `@next/eslint-plugin-next` and
  react-hooks. `eslint-config-next` is not used because its react/import/jsx-a11y plugins do not
  support ESLint 10, and ESLint 9 is out of support. Accessibility linting should return when
  those plugins support ESLint 10; Playwright covers basic accessibility roles meanwhile.
  pnpm 10 is pinned through `packageManager`.
- **D12 — Worker role check.** The worker refuses to start unless its role can execute the
  worker API and cannot bypass it (superuser, BYPASSRLS, direct `jobs` access). No override exists.
- **D13 — Generated schemas location.** `apps/ai-worker/src/jmos_worker/contract_schemas/`
  (package data), generated from `packages/core`, with a drift check in `verify`.

## Architecture gate required?

`no`. No domain relationship, authorization semantics, approval semantics or public contract
is changed. D2 and D8 are implementation choices and fail-closed defaults, recorded for review.

## Outcome (2026-09-30)

All acceptance criteria met locally. `pnpm verify` passes end to end in PGlite mode.
The CI workflow is written but has **not run yet** (no git remote), so the authoritative
real-Supabase run is still pending.

| Gate | Result |
|---|---|
| format / lint / typecheck (TS + Python) | pass |
| contracts drift | 1/1 up to date |
| unit — Vitest | 16/16 (core contracts, idempotency, protected-path policy) |
| unit — pytest | 24/24 (config, contracts, logging, runner incl. shutdown/outage) |
| db — pgTAP | 93/93 across 4 files (guards 12, tenancy RLS 27, queue 40, queue RLS 14) |
| acceptance (protected) | 0 files (convention ready; needs TEST_SPEC authority) |
| integration — worker ↔ Postgres | 4 passed, 1 skipped (least-privilege role test needs supabase mode) |
| build | pass |
| e2e — Playwright | 5/5 (desktop internal, mobile portal, health without worker) |

Mutation check: seven deliberately injected regressions each failed the pgTAP suites (missing RLS,
allow-all policy, anon grant, contributor leak, revoked membership honored, worker table grant,
fencing bypass).

Follow-ups owned by later increments are listed under Non-goals. Items that need a human:
branch protection and CODEOWNERS, the authority labels, and confirmation of D2 (queue transport).
