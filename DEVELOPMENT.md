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
