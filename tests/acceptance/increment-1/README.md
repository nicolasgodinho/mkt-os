# Increment 1 — Identity + Isolation: protected acceptance contract

Authority: `TEST_SPEC`. Builders must not edit these files (docs/11 "Protected paths").
Spec anchors: docs/01 (personas, capability model), docs/02 §1 and §7 (Identity), docs/05 §1, §2 and §6
(isolation, authorization, audit), docs/10 (Identity blueprint, RLS principle), docs/11
(mandatory invariants 1 and 9).

The tests run as pgTAP. Each file builds its own fixture inside a transaction that is rolled back.
Identities are impersonated the way PostgREST does it: JWT claims plus `SET ROLE authenticated`.
The database is the last barrier, so every test goes through RLS and the database API directly,
never through UI routing.

## Fixture (identical in every file)

| Tenant | Identity | Membership |
|---|---|---|
| Workspace A | `a_admin`, `a_admin2` | admin |
| | `a_account`, `a_strategist`, `a_creative`, `a_analyst` | the named internal role, no explicit capabilities |
| | `a_contributor` | contributor, no explicit capabilities |
| | `a_contrib_view` | contributor + explicit `client.view` |
| | `a_strat_mgr` | strategist + explicit `client.manage` |
| | `a_invited` | admin, status `invited` |
| Workspace B | `b_admin` | admin |
| Client A1 (workspace A) | `a1_cadmin` / `a1_approver` / `a1_collab` / `a1_viewer` | client_admin / approver / collaborator / viewer |
| | `a1_collab_appr` | collaborator + explicit `approval.decide` |
| Client A2 (workspace A) | `a2_viewer` | viewer |
| Client B1 (workspace B) | `b1_approver` | approver |
| none | `outsider`, `newbie` | no memberships |

## Database API frozen by these tests

Everything below is in schema `public`, executable by `authenticated` only (never `anon`), and
evaluated for the calling identity (`auth.uid()`). Tenant scope is **always derived from
memberships, never from caller-supplied ids**.

| Function | Requires |
|---|---|
| `workspace_capabilities(p_workspace_id uuid) → capability[]` | — (empty when not an active member) |
| `client_capabilities(p_client_id uuid) → capability[]` | — (empty when the client is not accessible) |
| `create_client(p_workspace_id uuid, p_name text, p_slug text) → uuid` | `client.manage` in the workspace |
| `update_client(p_client_id uuid, p_name text) → void` | `client.manage` |
| `archive_client(p_client_id uuid) → void` | `client.manage` (sets `status = 'archived'`) |
| `set_workspace_member(p_workspace_id uuid, p_user_id uuid, p_role workspace_role, p_capabilities capability[] default '{}') → void` | `workspace.manage` |
| `revoke_workspace_member(p_workspace_id uuid, p_user_id uuid) → void` | `workspace.manage` |
| `set_client_member(p_client_id uuid, p_user_id uuid, p_role client_role, p_capabilities capability[] default '{}') → void` | `client.manage` |
| `revoke_client_member(p_client_id uuid, p_user_id uuid) → void` | `client.manage` |

Table `audit_logs` (docs/05 §6, docs/10 Platform) has at least `workspace_id`, `client_id`,
`actor_id`, `action`, `target_id`, `created_at`. Membership changes append to it. Only workspace
members with `audit.view` can read it. Nobody can write it directly.

### Error contract (no existence leak)

| Situation | SQLSTATE | Message |
|---|---|---|
| Target not accessible to the caller (other tenant, or it does not exist) | `P0002` | `not found` |
| Target accessible, capability missing | `42501` | `permission denied` |
| No authenticated identity (no `sub` claim) | `42501` | (any) |
| Invalid argument (e.g. an internal capability on a client membership) | `22023` | (any) |

A guessed UUID of another tenant's row therefore produces exactly the same outcome as a random UUID.

### Capability semantics frozen here (spec-explicit parts only)

- **Admin** (Owner/Admin, docs/01: "can see all workspace data"): every capability in its own
  workspace, none anywhere else.
- **Contributor** (docs/01: "only sees clients/areas explicitly assigned"): no default
  capabilities. An explicitly granted capability takes effect.
- **High-risk capabilities** (docs/05 §2): `rule.activate`, `approval.decide`,
  `publication.schedule`, `publication.publish`, `integration.manage`, `workspace.manage`,
  `client.manage`, `admin.support`. They are never role defaults for account, strategist,
  creative or analyst; they must be granted explicitly.
- **Client roles** hold only client-safe capabilities (`client.view`, `approval.decide`,
  `request.submit`). Assigning an internal capability to a client membership is rejected (`22023`).
  - Approver decides approvals but never activates rules or edits strategy (docs/01).
  - Collaborator submits requests but does not approve unless `approval.decide` is granted separately.
  - Viewer is read-only: `client.view` only.

Role defaults that the spec does not state explicitly (for example, whether a strategist has
`client.view` by default) are **not** frozen here. They are builder decisions covered by builder
tests.

## Coverage deferred to the increment that creates the domain (not testable yet)

| Capability / invariant | Arrives with |
|---|---|
| `strategy.edit`, `knowledge.propose`, `knowledge.approve`, `rule.activate` enforcement | Increment 2 (Client Brain) |
| `content.create`, `content.edit`, `content.review_internal` | Increment 5 |
| `approval.request`, `approval.decide` enforcement, internal threads | Increment 6 |
| `publication.schedule`, `publication.publish` | Increment 7 / v0.6 |
| `integration.manage` | Increment 8 |
| `request.submit`, `request.triage`, `project.manage` | v0.2 |
| `admin.support` (impersonation audit) | when support tooling exists |
| Internal AI traces, margins/costs, unpublished strategic notes | the owning modules |
| Worker domain reads scoped to the leased job's tenant (ADR 0001) | the first worker read function (Increment 3/4) |
| Contributor per-client assignment | **pending architecture decision**: the domain model has no assignment entity |

Until then these capabilities are covered only at the resolution layer (`*_capabilities`).
