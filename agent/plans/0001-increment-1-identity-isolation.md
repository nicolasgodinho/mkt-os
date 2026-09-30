# ExecPlan 0001 — Increment 1: Identity + Isolation

Status: approved for build (autonomous run, 2026-09-30).
Spec anchor: `docs/13_MVP_BUILD_PLAN.md` → Increment 1 ("Workspace/User/Membership/Client; RLS;
internal/client shells; cross-tenant acceptance tests").
Contract: protected acceptance tests `tests/acceptance/increment-1/` (TEST_SPEC, commit
`1893602`, PR #5). Where the contract and this plan differ, **the tests win**. This plan never
edits them.

## Problem

After Increment 0 the tenancy tables and read policies exist, but nothing can be **written**
safely. There is no capability model, no authentication in the web app, and no audit of
permission changes. No later module can be built until identity, authorization and isolation
are real.

## Goal

Real authentication (Supabase Auth), the capability model (role defaults plus explicit
capabilities), a capability-checked database API for the Identity context, audit of membership
changes, and minimal internal and portal shells that run on real sessions. The evidence must show
that knowing or guessing another tenant's UUIDs never lets anyone read, change or operate on its
data.

## In scope

- Capability resolution in the database (single source of truth, no TS mirror).
- Capability-checked RPCs frozen by the TEST_SPEC: `workspace_capabilities`,
  `client_capabilities`, `create_client`, `update_client`, `archive_client`,
  `set_workspace_member`, `revoke_workspace_member`, `set_client_member`, `revoke_client_member`.
- `audit_logs` (append-only) for client and membership changes (docs/05 §6).
- An application profile created from the Auth identity (trigger on `auth.users`).
- Internal access predicates redefined on capabilities; jobs and worker-health visibility follow.
- Web: `@supabase/ssr` session handling (Next 16 `proxy.ts` refresh only; checks happen in the
  data layer), login/logout, internal shell (workspace, allowed clients, client context, empty,
  not-found/unauthorized), mobile portal shell (client identity, allowed areas, boundary).
- Deterministic dev/CI seed identities with local-only passwords.
- Builder tests: pgTAP (defaults, trigger, audit immutability, guards), Vitest (pure web helpers),
  Playwright (authenticated flows against real Supabase in CI), and the Auth + PostgREST boundary.

## Non-goals

Increment 2+ domains (Client Brain, knowledge, content, approvals workflow, calendar, Drive,
requests/projects). Also out of scope:
- member-management UI (the API exists; the UI arrives with settings);
- invites by email and the password-reset/sign-up UI (sign-in only);
- social login;
- workspace creation through the API (bootstrap by seed/operator);
- client self-service member management by Client Admin;
- per-client contributor assignment (see "Architecture decision pending").

## Relevant docs

00 §5 (BLOCKER isolation), 01 (personas, capability model), 02 §1 and §7, 05 §1, §2 and §6, 06
(navigation), 07 §14 (portal home hierarchy; no internal data), 09 (Supabase Auth/RLS), 10 (Identity,
Platform `audit_logs`, RLS principle), 11 (invariants 1 and 9), ADR 0001 (worker scope).

## Domain entities affected

Workspace, User (profile), WorkspaceMembership, Client, ClientMembership (docs/02 Identity), and
AuditLog (docs/02 Platform, blueprint `audit_logs`). **No new entity.**

## Schema / migrations

One additive migration, `supabase/migrations/20260930140000_identity_authorization.sql`:

- `app.workspace_role_defaults(workspace_role)` and `app.client_role_defaults(client_role)`:
  immutable default tables.
- `app.workspace_capabilities_of(uid, workspace)` and `app.client_capabilities_of(uid, client)`:
  resolution (active membership only; defaults ∪ explicit; sorted, distinct).
- `create or replace` of `app.has_internal_workspace_access`, `app.has_internal_client_access`
  and `app.is_internal_staff` so they are capability-based (`client.view`). Same signatures and
  grants, so the protected guard 000 allowlist is unchanged.
- `public.audit_logs` with a composite FK pinning `client_id` to the workspace, an immutability
  trigger, RLS `select` for `audit.view` holders, and no write grants.
- `app.handle_new_auth_user()` trigger on `auth.users` → `public.users` (display name from user
  metadata; e-mail is not copied).
- The nine RPCs above, plus internal helpers (`app.require_uid`, `app.audit`).
- `alter default privileges … in schema public revoke execute on functions from public, anon`, so
  future public functions are not callable by anon by default.

Existing migrations are **not** modified.

## Relationships

Unchanged. Client → Workspace (composite FK already present). Membership → user/workspace/client.
Audit → workspace (+ client via the composite FK). Internal members (workspace memberships) and
client-side members (client memberships) stay separate: a user with an active internal membership
in the client's workspace cannot be given a client membership there.

## Authorization model (docs/01 "role defaults + explicit capabilities")

Effective capabilities = role defaults ∪ explicit `capabilities`, and only while the membership
is `active`.

| Workspace role | Defaults |
|---|---|
| admin (Owner/Admin) | all 20 |
| account | client.view, knowledge.propose, approval.request, request.submit, request.triage, project.manage |
| strategist | client.view, strategy.edit, knowledge.propose, content.create |
| creative | client.view, content.create, content.edit, content.review_internal |
| analyst | client.view, knowledge.propose |
| contributor | none |

| Client role | Defaults | Allowed explicit extras |
|---|---|---|
| client_admin | client.view, approval.decide, request.submit | client-safe set only |
| approver | client.view, approval.decide | client-safe set only |
| collaborator | client.view, request.submit | client-safe set only |
| viewer | client.view | client-safe set only |

The client-safe set is {`client.view`, `approval.decide`, `request.submit`}. The high-risk
capabilities of docs/05 §2 are never defaults for account, strategist, creative or analyst.

- **Internal access to a client:** the workspace's effective capabilities contain `client.view`.
  The client then inherits the workspace capabilities.
- **Client-side access:** an active client membership.

The spec-explicit rows are frozen by TEST_SPEC. The remaining defaults are builder decisions
(D1 below) and are covered by `supabase/tests/database/030_*`.

## RLS strategy

Tables keep read-only grants and policies. Writes happen **only** through the SECURITY DEFINER RPCs,
each of which:
1. requires `auth.uid()`;
2. derives the tenant from the target row (never from payload ids);
3. returns `P0002 not found` when the caller cannot access the target (other tenant or
   nonexistent, so the two are indistinguishable);
4. returns `42501 permission denied` when the target is accessible but the capability is missing;
5. validates input (`22023`);
6. writes the change and its audit row in the same transaction.

All definer functions use `set search_path = ''`. Their EXECUTE is revoked from PUBLIC/anon and
granted to `authenticated` only. The `audit_logs` policy uses `public.workspace_capabilities(...)`,
which authenticated may already execute, so the protected app-schema allowlist is untouched.

## State implications

Membership status: `invited` → `active` → `revoked`. Only `active` grants anything; a revocation
takes effect on the next statement (no cache).

Client status: `active` → `archived` (soft delete, docs/05 §7). Archived clients stay visible to
authorized internal members.

Guard rails: a workspace always keeps at least one active admin, and an actor cannot change their
own membership.

## API / application-service boundaries

The database API is the application service for Identity. The web app calls it with the **user's**
session through PostgREST (`@supabase/ssr`). The web app never uses the service role. No domain
events are needed yet: no asynchronous consumer exists, so there is no outbox (ADR 0001 / Increment 3).

## UI surfaces

**Internal (desktop-first)**
- `/login`, `/logout` (POST)
- `/` → redirect to the first workspace, or to the portal, or show "no access"
- `/w/[workspace]`: workspace switcher, allowed clients, empty state
- `/w/[workspace]/clients/[clientId]`: client context (identity, status, my capabilities)
- not-found for anything inaccessible

**Portal (mobile-first)**
- `/portal` → own client(s)
- `/portal/[clientId]`: client identity, permitted areas derived from capabilities, logout
- not-found for other clients and internal routes

## Failure states

- Missing or expired session → redirect to `/login` (the proxy refreshes tokens).
- Supabase not configured → login shows "authentication not configured".
- Inaccessible route or id → 404 page with no tenant data (same page for nonexistent resources).
- RPC errors mapped to generic messages.
- DB down → error boundary without internals.

## Definition of Done / acceptance criteria

1. All `tests/acceptance/increment-1` files pass on real Supabase (CI) and on PGlite locally,
   **unmodified** (`git diff 1893602 -- tests/acceptance` is empty).
2. Mutation proof: each listed security mutation makes at least one acceptance test fail.
3. `pnpm verify` is green locally and in CI (Supabase mode), including authenticated E2E in CI.
4. Domain, security and UI reviews have no open BLOCKER, HIGH or MEDIUM findings.

## Tests

- **pgTAP acceptance** (frozen).
- **pgTAP builder** `030_identity_authorization`: default tables, profile trigger, audit
  immutability, last-admin and self-change guards, internal/client separation, slug validation,
  grants on the new functions.
- **Vitest**: safe redirect paths, Supabase status parsing, portal areas from capabilities, error
  mapping.
- **Playwright** (authenticated specs need real Supabase and skip locally with a stated reason):
  - internal: login → workspace → allowed client → other workspace/client 404 → contributor
    empty → logout;
  - portal: login → own client → other client 404 → internal route 404 → forbidden RPC via the
    real PostgREST boundary → logout;
  - unauthenticated redirects.

## Observability / audit

`audit_logs` records workspace, client, actor (`auth.uid()`), action, target, before/after (role,
capabilities, status, name) and time. There are no secrets and no e-mail addresses in it. Web
errors are logged server-side without tokens.

## Rollout / migration impact / rollback

Additive migration only. The seed changes (local/CI only). Rollback = revert the web changes and
add a new migration dropping the new functions and table (no data loss beyond the local seed).
No production exists yet.

## Risks

- **Local verification gap.** The dev machine has no Docker, so authenticated E2E and PostgREST
  behavior are verified only in CI.
- **Local key discovery.** `next.config.ts` discovers local Supabase keys through
  `supabase status` when no env is set. It must never select server-only keys; only the URL and
  the public anon/publishable key are read.
- **Registry rate limit** (`public.ecr.aws`, known operational debt): CI restarts are external
  failures, not regressions.

## Decisions (reversible)

- **D1.** The default capability table above. It is spec-consistent; the non-frozen rows can be
  tuned by a human without TEST_SPEC.
- **D2.** Writes go only through RPCs, with no direct DML grants. This is the smallest attack surface.
- **D3.** The profile has no e-mail. Display name comes from auth metadata.
- **D4.** Archived clients remain readable to authorized members. Portal behavior for archived
  clients is revisited with the offboarding flow (docs/15).
- **D5.** Seed passwords are local/CI-only constants documented as such.

## Architecture decision pending (not blocking this increment)

**Contributor per-client assignment.** docs/01 says contributors see only "explicitly assigned"
clients, but docs/02 and docs/10 contain no assignment entity (ClientMembership models client-side
personas; Task arrives in v0.2). Implemented behavior is **fail-closed**: a contributor sees no
client unless an admin explicitly grants `client.view`, which is workspace-wide. Options for a
human decision (ADR):
1. new `ClientAssignment` entity;
2. an internal role value on ClientMembership;
3. derive assignment from Task assignment (v0.2).

## Architecture gate required?

`no` for everything implemented. The contributor assignment above is surfaced for an ADR and not
implemented.
