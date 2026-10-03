# Development guide — Jansen Marketing OS

Operational guide for developers and coding agents. The product and engineering authority is
the frozen specification (`README.md`, `AGENTS.md`, `/docs`). This file only explains how to
run the repository.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Node.js | ≥ 22.12 | `.nvmrc` pins major 22 |
| pnpm | 10.x | pinned by `packageManager`; `corepack enable` or `npm i -g pnpm@10` |
| Python | ≥ 3.12 | for the AI Worker; set `JMOS_PYTHON` if it is not on PATH |
| Docker | any recent | needed for the real Supabase stack. Without it, DB tests fall back to PGlite (see below) |

## First-time setup

```bash
pnpm install                              # JS/TS dependencies (+ Supabase CLI binary)
pnpm setup:py                             # apps/ai-worker/.venv with the worker + dev tools
pnpm exec playwright install chromium     # browser for E2E
cp .env.example .env.local                # optional local overrides (git-ignored)
```

## Everyday commands

| Goal | Command |
|---|---|
| Web app (internal at `/`, portal at `/portal`) | `pnpm dev` → http://localhost:3000 |
| Start Supabase (full local stack, Docker) | `pnpm exec supabase start` (Studio: http://127.0.0.1:54323) |
| Start only the database | `pnpm exec supabase db start` |
| Stop Supabase | `pnpm exec supabase stop` |
| Reset DB: migrations + seed from empty | `pnpm db:reset` |
| DB + RLS tests (pgTAP) | `pnpm db:test` (runs a reset first) |
| Unit tests (Vitest + pytest) | `pnpm test:unit` |
| Worker ↔ Postgres integration tests | `pnpm test:integration` |
| Protected acceptance tests (TS) | `pnpm test:acceptance` |
| E2E (production build) | `pnpm build && pnpm test:e2e` |
| Run the AI Worker | `pnpm worker` (needs `JMOS_WORKER_DATABASE_URL`) |
| Check worker config/role | `pnpm --filter @jmos/ai-worker check` |
| **Everything, in CI order** | **`pnpm verify`** |

`pnpm verify` runs format → lint → typecheck → contracts → unit → db (migrations, pgTAP/RLS,
protected acceptance SQL) → acceptance (TS) → integration → build → e2e. It stops at the first
failure and prints a summary. CI runs the same command.

## Database modes (`JMOS_DB_MODE`)

- `supabase` is the real local Supabase stack. It is **authoritative** and CI always uses it.
  `db:test` runs `supabase db reset` (a clean database) and then the pgTAP suites.
- `pglite` is Postgres compiled to WASM, in-process. It runs the same migrations, seed and pgTAP
  files after a minimal Supabase compat bootstrap (`scripts/db/pglite-supabase-compat.sql`).
  Use it when Docker is unavailable. It is **not authoritative**:
  - Connections share one backend session, so concurrent-worker behavior (`SKIP LOCKED`) is
    only exercised against real Postgres.
  - It has a single superuser, so the worker's least-privilege integration test is skipped.
    pgTAP still checks the role grants.
- `auto` (default) uses supabase when its database answers on `JMOS_DB_URL`, otherwise pglite,
  and prints a warning banner.

## Authentication and identities (Increment 1)

- The web app uses **Supabase Auth** (e-mail + password) through `@supabase/ssr`. `src/proxy.ts`
  only refreshes the session. Every page checks the session itself, and all data is read with the
  user's session, so **Postgres RLS decides what is returned**. The web app never uses a
  service-role key.
- Configuration: `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. When they
  are not set, `next.config.ts` asks the local Supabase CLI (`supabase status`) for the local URL
  and **public** key only. Without a local stack, `/login` says authentication is not configured.
  Deployed environments must always set the variables.
- Writes to the Identity context go only through the capability-checked database API
  (`create_client`, `set_workspace_member`, … — see `tests/acceptance/increment-1/README.md`).
  Inaccessible targets answer `P0002 not found`, exactly like missing ones.
- Signing out ends only the current browser's session (`scope: 'local'`). Supabase's default would
  revoke every session of the user, including other devices and parallel E2E workers.
- Seeded local identities (password `jmos-local-dev-password`, local/CI only):

  | E-mail | Access |
  |---|---|
  | `admin@jansen.local` | Owner/Admin of workspace `jansen` |
  | `strategist@jansen.local` | strategist (`jansen`) |
  | `contributor@jansen.local` | contributor: no client until explicitly granted |
  | `revoked@jansen.local` | revoked internal member |
  | `client-admin@cliente-a.local`, `approver@cliente-a.local`, `collaborator@cliente-a.local` | Cliente Demo A portal roles |
  | `revoked@cliente-a.local` | revoked client member |
  | `viewer@cliente-b.local` | Cliente Demo B viewer |
  | `admin@outra-agencia.local`, `viewer@cliente-c.local` | second workspace and its client |

- Authenticated E2E specs (`auth.*.spec.ts`, `boundary.internal.spec.ts`) need the real Supabase
  stack. Locally without Docker they are skipped with a stated reason. In CI
  (`JMOS_DB_MODE=supabase`), a missing stack fails them.

## Client Brain (Increment 2)

- **Where it lives.**
  - UI: `/w/<workspace>/clients/<client>/brain` (Visão geral, Conhecimento, Regras). It is
    internal-only; client roles get the shared 404.
  - Code: `apps/web/src/lib/brain/` (queries, actions, form parsing, error mapping).
- **How it is written.**
  - All writes go through the SECURITY DEFINER API frozen in
    `tests/acceptance/increment-2/README.md`. The tables have no write privileges for API roles.
  - Knowledge and rules always enter as **proposed**.
  - Facts, decisions and insights need `knowledge.approve`. Rules need `rule.activate`. By
    default only admins hold these two (grant them explicitly to others).
- **Rules: conflicts and resolution.**
  - Opposite MUST and MUST NOT rules on the same `subject` conflict when they also share scope
    and priority and their validity overlaps. Both leave `effective_rules` until a person
    rejects or supersedes one side.
  - A channel rule shadows the client rule for its subject. A higher priority wins within the
    same scope.
- **Trust.** Sources marked `UNTRUSTED_EXTERNAL` can back insights, but never facts, decisions
  or rules.
- **Local data.** The seed gives Cliente Demo A a small Brain: brand profile, audience, offer,
  region, two sources, facts, a decision, an insight and rules.
- **E2E.** `brain.internal.spec.ts` uses unique subjects and statements per run, so it can run
  repeatedly on the same database.

## Job center (Increment 3)

- **Where.** `/w/<workspace>/automations` (Automações). It shows:
  - worker health: online when a heartbeat arrived in the last 60 s; the active model profile;
  - per-status counts, including *stalled* (running with an expired lease);
  - recent jobs and their last error.
- **Who.**
  - Internal staff with `client.view` can read the job center.
  - Requesting the allow-listed system jobs (`system.healthcheck`, `ai.model_check`), and
    canceling or retrying jobs, needs `workspace.manage`. All of these go through the database
    API frozen in `tests/acceptance/increment-3/README.md`.
- **Retries.** A retry never resets the attempt count: attempt numbers fence stale workers
  (ADR 0001).
- **Model runtime.** See `apps/ai-worker/README.md` for the adapter and Ollama setup.

## Content core (Increment 5)

- **Where.** The UI lives at `/w/<workspace>/clients/<client>/content`, with three sections:
  - Pautas e conteúdos;
  - Oportunidades;
  - Iniciativas.

  Each pauta has a detail page that shows its Definition of Ready. Each content item opens in the Content Studio.
- **Flow.** An opportunity is converted into a pauta. A pauta becomes ready only after it meets the Definition of Ready: objective, audience, message or angle, and CTA. Content can only be created from a ready pauta. Submitting content creates an immutable revision (a trigger refuses UPDATE and DELETE). The internal review then approves that exact revision.
- **Rule validator.** Before approval, a reviewer checks every effective MUST and MUST_NOT rule for the client and the channel. Approval is blocked if any of these hold:
  - a rule is not checked;
  - a MUST_NOT rule is violated;
  - a relevant rule conflict is open.

  Soft rules never block.
- **Seed.** Cliente Demo A has an approved post. Cliente Demo B has a post waiting for review that violates its MUST_NOT price rule.

## Collaboration and client portal (Increment 6)

- **Sending to the client.** In the Content Studio, "Aprovação do cliente" sends the internally approved revision to the client (`approval.request`). A content has at most one open request.
- **Where.**
  - Internal staff see every request at `/w/<workspace>/approvals` (Aprovações).
  - Client approvers see "Precisa de você" on `/portal/<client>`, the list at `/portal/<client>/approvals`, and the approval screen for each request.
- **Who decides.** Only a client-side member with `approval.decide` approves or asks for changes. Internal grants never count. A decision is immutable and targets the exact revision that was sent.
- **Stale requests.** If the team edits the content or sends it back to production while the client is reviewing, the open request becomes `canceled`. The client then sees a notice instead of the decision buttons.
- **Comments.** Each content has an internal thread (staff only) and a client thread. Approvers and collaborators can write in the client thread; viewers only read it. Clients never see internal comments.
- **Contract.** `tests/acceptance/increment-6/README.md`.
- **Seed.** Cliente Demo A has a story waiting for the client's approval.

## Calendar and publication (Increment 7)

- **Where.**
  - Internal staff use `/w/<workspace>/calendar` (Calendário), with month and list views and filters for client and event type. Below the calendar, "Aprovados sem data de publicação" lists content the client approved that is not scheduled yet.
  - Each content has a "Publicação" section in the Content Studio.
  - Clients see "Próximos 7 dias" on `/portal/<client>` and the next 30 days at `/portal/<client>/calendar`.
- **Typed dates.** The calendar projects four event types: publication, production deadline, approval deadline and meeting. Each date changes only through its own record's action:
  - moving a publication date never moves the production deadline;
  - moving the production deadline never moves a publication.
- **Scheduling.**
  - Only content whose latest approved revision was approved by the client can be scheduled (`publication.schedule`). The publication pins that revision.
  - A content can have several publications. Canceling the last one returns the content to `approved`.
  - Scheduled content cannot be edited; cancel its publications first.
- **Publishing.** v0.1 has no social publishing. A person with `publication.publish` records the publication as published, with an optional link. This never changes the revision.
- **Who sees what.** Clients see their publications and approval deadlines. Production deadlines and meetings stay internal.
- **Contract.** `tests/acceptance/increment-7/README.md`.
- **Seed.** Cliente Demo A has a client-approved post scheduled in 3 days, with a production deadline tomorrow.

## Drive sync (Increment 8)

- **Where.** `/w/<workspace>/clients/<client>/drive` shows the connection, its sync state and the file registry. It is internal only.
- **Connecting.** It requires `integration.manage`. Paste the folder link or id, a credential reference (default `default`) and an interval of 15 to 1440 minutes. Connecting queues the first sync. A folder can be connected to only one client.
- **How a sync runs.** The AI Worker runs it as a `drive.sync` job (ADR 0004).
  - It lists the folder tree and returns metadata only. The database applies the snapshot exactly once.
  - New or changed files become "Aguardando indexação". Files missing from the snapshot become "Removido do Drive".
  - The next sync is queued after the interval.
- **Failure states.** A failed sync keeps its error code on the job. The Drive page explains it, and the job center shows it. "Sincronizar agora" retries it.
- **Credentials.** See `apps/ai-worker/README.md` ("Drive sync"). Keys live at `$JMOS_DRIVE_CREDENTIALS_DIR/<workspace id>/<ref>.json`. Without them, syncs fail with `drive_credentials_missing`. That is expected in local development.
- **Re-index.** "Indexar de novo" puts a file back to "Aguardando indexação". Indexing itself arrives with the RAG increment.
- **Contract.** `tests/acceptance/increment-8/README.md`.
- **Seed.** Cliente Demo A has a connected folder with two files and one removed file. No sync is queued.

## Administration and invitations (Increment 9)

- **Where.**
  - `/w/<workspace>/settings` (Configurações) has two tabs:
    - **Equipe**: members, roles and extra capabilities, revoke access, invite people, pending invitations. It needs `workspace.manage`.
    - **Clientes**: create, rename and archive clients. It needs `client.manage`.
  - Each client's portal access lives at `/w/<workspace>/clients/<client>/access`. It needs `client.manage`.
- **Invitations.**
  - Creating one shows a link `/convite/<token>` once. Send it to the person.
  - The link expires in 7 days and works only for the invited e-mail.
  - Inviting the same e-mail again replaces the pending invitation.
- **Signup is invite-only** (ADR 0005). Supabase Auth runs `public.hook_before_user_created` before creating an account, and the hook refuses any e-mail without a pending invitation. The app never uses a service-role key.
- **Accepting.**
  - A new person creates the account on the invitation page and is taken to the workspace or the portal.
  - Someone with an account signs in, opens the link and clicks "Aceitar convite".
  - Acceptance requires the invited, **confirmed** e-mail. Local Supabase auto-confirms; production must keep confirmations on (see `DEPLOYMENT.md`).
- **Links.** They use `JMOS_PUBLIC_URL` when it is set, otherwise the request's host.
- **Contract.** `tests/acceptance/increment-9/README.md`.

## Repository layout

```text
apps/web            Next.js (App Router): internal OS shell `(internal)`, client portal `portal/`
apps/ai-worker      Python AI Worker (queue consumer, outbound-only)
packages/core       Shared contracts: job payload schemas (zod), idempotency keys
packages/ui         Design tokens + primitives (AppShell, Sidebar, PageHeader, StatusBadge, EmptyState)
supabase/           config.toml, migrations (append-only), seed.sql (local only), tests/database (pgTAP)
tests/e2e           Playwright specs (desktop internal, mobile portal)
tests/acceptance    PROTECTED executable invariants (TEST_SPEC authority only)
scripts/            verify, DB harness, contract generation, Python runner, CI policy
agent/plans         ExecPlans (one per substantial feature)
```

Module packages from `docs/09` (identity, knowledge, content, …) are created by the increment
that first needs them. Do not add empty packages.

## Rules that the tooling enforces

- **RLS on every table.** `supabase/tests/database/000_platform_guards.test.sql` fails if a
  `public` table lacks RLS, if a policy is allow-all or targets `anon`/all roles, if `anon` has
  any table privilege, if a SECURITY DEFINER function lacks a pinned `search_path`, or if the
  worker role gains anything beyond the worker API.
- **New table checklist:** enable RLS; add explicit policies per role (no `true`); `revoke all …
  from anon, authenticated` then grant only what is needed; carry `workspace_id` and/or a
  resolvable `client_id` pinned with a composite FK to `clients (id, workspace_id)`; add
  negative pgTAP tests (cross-workspace, cross-client, guessed UUIDs, client roles, anon).
- **Migrations are append-only.** CI rejects edits, renames and deletions of existing migration
  files, and new files must be named `YYYYMMDDHHMMSS_snake_case.sql` and sort last.
- **Protected authority** (docs/11, docs/12). A PR touching these paths needs a human-applied label:
  - `tests/acceptance/` → `authority:TEST_SPEC`
  - spec and agent rules (`docs/`, `AGENTS.md`, `CLAUDE.md`, `PLANS.md`), repository and CI
    policy (`.github/`, `scripts/ci/`), and the **verification contract** (`scripts/verify.mjs`,
    `scripts/db/`, `vitest.config.ts`, `playwright.config.ts`, the platform guard tests
    `supabase/tests/database/000_*` and `001_*`, and the `scripts` of any existing
    `package.json`) → `authority:ARCHITECTURE_CHANGE`

  The required `authority` check (`.github/workflows/authority.yml`) runs on
  `pull_request_target`, so its definition and policy code always come from the **base
  branch**: a PR cannot edit or remove its own check. The same policy also runs inside
  `verify` for defense in depth. Labels are applied by a human (Nicolas); agents never apply
  `authority:*` labels. Builders may add new tests and change feature tests freely; only the
  gates themselves are protected.
- **Contracts are generated, never hand-copied.** Job payload schemas live in `packages/core`
  (zod). `pnpm contracts:generate` writes the JSON Schema used by the Python worker, and
  `pnpm contracts:check` (part of verify) fails on drift.
- **No escape hatches.** ESLint forbids `any`, `@ts-ignore` and empty `catch`; mypy runs in strict
  mode; ruff forbids blind `except` unless the error is logged.

## Adding a background job type

1. Define the contract in `packages/core/src/jobs/` (`defineJobContract`: `type`, `schemaVersion`,
   strict zod `input`/`output`) and add it to `registry.ts`. Never edit a published version; add `v2`.
2. `pnpm contracts:generate`.
3. Implement the handler in `apps/ai-worker/src/jmos_worker/handlers.py` and register it by
   contract key (`type.vN`). Handlers must be safe to run twice (at-least-once delivery).
   Domain writes must commit in the same transaction as completion, through a dedicated
   `worker.*` SQL function that checks the lease.
   `jobs.result` is a small diagnostic summary only. Domain outputs (proposed facts, drafts, …)
   belong in their domain tables, never in `jobs.result` (docs/08 §1: AI is a service layer,
   not the data model).
4. Enqueue with a deterministic key from `jobIdempotencyKey(contract, parts)`.
5. Tests: contract unit tests, handler unit tests (FakeQueue), a pgTAP test for any new SQL,
   and an integration test.

## Git workflow

`main` is protected: every change goes through a pull request, and the required `verify`
check (the same `pnpm verify`, against real Supabase) must pass on a branch that is up to date
with `main`. Force pushes and branch deletion are blocked, and the rules apply to admins too.

```text
feature branch / worktree → implement → pnpm verify → review → PR → CI (verify) → merge
```

- Branch names: `feat/…`, `fix/…`, `chore/…`, `adr/…`, `test-spec/…`.
- Never commit directly to `main`, and never rewrite its history.
- The baseline is commit `67b6163` (Increment 0). Migrations up to that commit are historical.

## GitHub configuration (current)

| Setting | Value |
|---|---|
| Branch protection on `main` | PR required (0 approvals, see note), `verify` and `authority` required, strict up-to-date, conversation resolution, admins included, no force push, no deletion |
| Labels | `authority:TEST_SPEC`, `authority:ARCHITECTURE_CHANGE` |
| CODEOWNERS | `.github/CODEOWNERS` (protected paths → `@nicolasgodinho`) |

Note: required approvals are 0 because the repository has a single maintainer and GitHub does
not let an author approve their own PR. When a second maintainer joins, raise the count to 1
and enable "Require review from Code Owners".

Production and staging (when they exist): give `jmos_worker` a secret password through the
platform's secret management (`alter role jmos_worker with login password …`). The seed password
is local-only. Never apply `supabase/seed.sql` to a network-reachable database: if Supabase
Branching or preview databases are enabled, disable seeding there, or remove the worker login
from the seed first. Connect the worker directly or through the pooler; it does not use server-side
prepared statements, so transaction-mode pooling works.
