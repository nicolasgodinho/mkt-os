# ExecPlan 0002 — Increment 2: Client Brain basics

Status: **approved** by Nicolas on 2026-10-01 ("pode seguir"), including the four product decisions
and the Builder-level decisions below. The Builder is in progress.
Spec anchor: `docs/13_MVP_BUILD_PLAN.md` → Increment 2 ("Brand/Audience/Offer/Region;
Source/Fact/Decision/Rule/Insight; proposed → approved workflow; knowledge UI").
Contract: protected acceptance tests `tests/acceptance/increment-2/` (TEST_SPEC, commit `6ed762f`, PR #10, branch
`test-spec/increment-2-client-brain`). Where the contract and this plan differ, **the tests win**.
This plan never edits them.

## Problem

Identity and isolation exist, but the agency cannot record anything about a client. There is no
brand, audience, offer, region, source, fact, decision, rule or insight. Every later module
(pautas, the AI worker, the rule validator) reads this context. Without a governed Client Brain,
"learning" would be silent and unaudited, which docs/00 §4 and §5 forbid.

## Goal

A governed, internal-only Client Brain:
- **strategy context** (brand profile, audiences, offers, regions), edited by `strategy.edit`;
- **knowledge** (sources with trust levels; facts, decisions and insights) that always enters as
  *proposed* and becomes active only through an audited approval (`knowledge.approve`);
- **rules** (MUST, MUST_NOT, PREFER, AVOID) that are versioned, activated only by
  `rule.activate`, superseded atomically, and protected by deterministic structural conflict
  detection;
- **an internal UI** that shows provenance and status, keeps proposed items visually distinct and
  makes conflicts prominent.

## Product decisions (Nicolas, 2026-10-01; frozen in the TEST_SPEC README)

1. **Structural conflict key.** Hard rules require a `subject`. Opposite polarity on the same
   client, scope, subject and priority, with overlapping validity and no supersession, puts
   both rules in `conflict`, outside the effective set, until a human rejects or supersedes one.
2. **Proposed-first.** All knowledge enters as `proposed`, even from admins. Approval or
   activation is a separate audited call.
3. **Internal-only.** Client roles see nothing of the Client Brain in Increment 2.
4. **Untrusted ≠ truth.** Facts, Decisions and Rules backed by `UNTRUSTED_EXTERNAL` sources cannot
   be approved or activated. Insights can.

## In scope

- One additive migration: enums, 9 tables, RLS (internal read only), no direct write
  privileges, SECURITY DEFINER API (16 functions) frozen by the TEST_SPEC README.
- Audit entries (docs/05 §6):
  - knowledge proposal, approval and rejection;
  - rule proposal, activation, supersession, rejection, conflict detected and conflict resolved;
  - strategy context saves and archives;
  - source creation.
- Builder pgTAP (`040_client_brain`):
  - grants;
  - table constraints (same-client source FK, hard-rule subject check, channel check);
  - the conflict-recompute edge cases not frozen by the TEST_SPEC: different subject on
    supersession; MUST+MUST is not a conflict;
  - the advisory lock serializing rule changes per client.
- Internal UI under `/w/[workspace]/clients/[clientId]/brain`:
  - **Overview:** sections Business, Brand, Audience, Offers, Regions, Voice and visual
    references.
  - **Knowledge:** list with type, status and source filters; propose form; approve and reject
    actions shown only when `knowledge.approve` is held.
  - **Rules:** list with type, scope, status and validity filters; propose form; activate and
    reject actions only with `rule.activate`.
  - **Conflicts:** a banner on top of the Brain pages whenever `rule_conflicts` is non-empty.
  - **Effective rules:** a preview per channel.
- Seed: a small Client Brain for client A (local and CI only) so the UI and E2E have data.
- E2E (authenticated, CI):
  - a strategist proposes a fact; the admin approves it and it shows as active;
  - the admin activates a rule; a conflicting activation shows the conflict banner; rejecting one
    side clears it;
  - a client user gets 404 on the Brain routes.

## Non-goals (deferred, with destination)

| Item | Where |
|---|---|
| Workspace-, initiative- and content-scoped rules | Increment 5 (Initiative/Content exist) |
| Evaluating `exception_expression` (column stored, never evaluated) | Increment 5 rule validator |
| Publish-ready MUST_NOT hard block (docs/11 invariant 3) | Increment 5 |
| AI or meeting proposals into the Brain (docs/11 invariant 4) | Increment 4, on this proposed-first API |
| `rule.activated` domain event / outbox | first asynchronous consumer (Increment 3+, ADR 0001) |
| Goals, Hypotheses, Examples, KnowledgeLinks | when a module needs them |
| Portal visibility of strategy | later increment with its own TEST_SPEC |
| Automatic `expired` status transition | rule validator / scheduler; effective resolution already ignores rules outside their window |
| File uploads for sources (`file_id`) | Assets increment; `uri` only now |

## Relevant docs

- docs/00 §4–5;
- docs/01 (capabilities);
- docs/02 §3–6;
- docs/04 (Rule);
- docs/05 §1, §2, §4, §6, §7;
- docs/07 §4 and §12;
- docs/10 (Strategy, Knowledge);
- docs/11 (required negative "Approver cannot activate Rule");
- docs/13 Increment 2;
- ADR 0001 (no outbox yet);
- ADR 0002 (contributor fail-closed).

## Domain entities affected

New entities:
- strategy context: BrandProfile, Audience, Offer, Region;
- knowledge: Source, Fact, Decision, Insight, Rule.

All are client-scoped. No existing entity, relationship or role meaning changes. The capability
enum already contains `strategy.edit`, `knowledge.propose`, `knowledge.approve` and
`rule.activate` (Increment 0), and the D1 default table is unchanged. As a result, **only admins
hold `knowledge.approve` and `rule.activate` by default**. Others need an explicit grant (the
TEST_SPEC uses a strategist with an explicit `knowledge.approve`).

## Schema / migrations

One new migration, `2026100112xxxx_client_brain.sql`, additive only.

- **Enums:** `context_status`, `source_type`, `source_trust`, `knowledge_kind`,
  `knowledge_status`, `rule_type`, `rule_scope` (`client | channel`), `rule_status`.
- **`brand_profiles`:** unique `client_id`.
- **`audiences`, `offers`, `regions`:** `status` = `active | archived`. Offers carry
  `valid_from`/`valid_until` (date).
- **`sources`:**
  - `trust_level` can never be `SYSTEM` from the API (reserved for future system writers);
  - `unique (id, client_id)`.
- **`facts`, `decisions`, `insights`:**
  - `source_id` references `sources (id, client_id)` through a composite FK, so a source of
    another client is impossible even for a buggy function;
  - `approved_by` is set on approval.
- **`rules`:**
  - `subject` is normalized lowercase, required for MUST and MUST_NOT (check constraint);
  - `scope_type`/`channel` must agree (check constraint);
  - `priority` is 0..100 (default 50);
  - `effective_from`/`effective_until` form a half-open window;
  - `supersedes_rule_id` references `rules (id, client_id)` through a composite FK;
  - also `approved_by`, `activated_at` and `exception_expression` (stored only).
- **Triggers:** `updated_at` on every mutable table.
- **Data migration:** none.

## Authorization model

Unchanged from Increment 1. The order of checks is frozen in the README:
1. Target: a visible client, or a readable item. Otherwise P0002.
2. Capability. Otherwise 42501.
3. Arguments and references. P0002 for a foreign reference, 22023 for invalid input or state.

| Operation | Capability |
|---|---|
| Strategy writes and archive | `strategy.edit` |
| Sources and proposals (facts, decisions, insights, rules) | `knowledge.propose` |
| Approve or reject facts, decisions, insights | `knowledge.approve` |
| Activate or reject rules (hard and soft; supersession is activation) | `rule.activate` |
| Read tables, `effective_rules`, `rule_conflicts` | internal access to the client (`client.view`) |

## RLS strategy

- **Read policy:** one per table, `for select to authenticated using
  (app.has_internal_client_access(client_id))`.
- **Write privileges:** `revoke all` from anon and authenticated, then `grant select` to
  authenticated.
- **Functions:**
  - every function sets `search_path = ''`;
  - public functions are EXECUTE for `authenticated` only;
  - helpers in `app` are revoked from everyone.
- **Worker:** `jmos_worker` gets nothing. The Increment 1 acceptance test 150 already asserts that
  generically for every public table and function.

## State implications

- **Knowledge:**
  - `proposed → active`, needs `knowledge.approve`; blocked for untrusted facts and decisions;
  - `proposed → rejected`;
  - any other transition is 22023.
- **Rules (docs/04):**
  - `proposed → active | conflict`, through `activate_rule`;
  - `active | conflict → superseded`, when a superseding rule is activated, in the same
    transaction;
  - `active ↔ conflict`, through deterministic recomputation after every activation, rejection
    and supersession of a hard rule;
  - `proposed | conflict → rejected`;
  - `superseded` and `rejected` are terminal;
  - `expired` is reserved (see Non-goals).
- **Concurrency:** rule changes take a transaction-scoped advisory lock per client. Two
  concurrent opposite activations therefore cannot both end `active`.

## API / application-service boundaries

The database API is the application service, as in Increment 1. The web app calls it with the
user's session (never the service role). Server actions validate input with zod, then call the
RPC, then map errors (P0002 → 404, 42501 → "sem permissão", 22023 → field or state message).
There are no events (Non-goals).

## UI surfaces (internal, desktop-first; docs/07 §4 and §12)

- **Brain sub-navigation** in the client context: Visão geral, Conhecimento, Regras.
- **Visão geral:**
  - the brand profile form;
  - lists and forms for audiences, offers (with validity) and regions;
  - archive actions.
- **Conhecimento:**
  - a table with type, statement, source with trust badge, status and validity;
  - filters for type, status, source and trust;
  - "Proposto" items use a distinct StatusBadge tone;
  - forms to register a source and to propose a fact, decision or insight;
  - approve and reject buttons.
- **Regras:**
  - a table with type, subject, scope/channel, priority, validity, status and source;
  - filters for type, scope, status and validity;
  - a propose form (subject required for MUST and MUST_NOT; a supersede selector);
  - activate and reject buttons;
  - an effective-rules preview with a channel selector.
- **Conflict banner** (role=alert) on all Brain pages, listing the conflicting pairs with
  resolution actions.
- **Gating and errors:**
  - every action is hidden when the capability is missing, and the server enforces it anyway;
  - not-found for inaccessible clients, as in Increment 1.

The UI reuses `packages/ui` (PageHeader, StatusBadge, EmptyState, Button, TextField). It adds
small `Select`/`TextArea` components only if needed.

## Failure states

- An inaccessible client or item → 404 page.
- A missing capability → the action is hidden; a forced POST returns a generic "sem permissão".
- An untrusted approval or activation → an inline message explaining the trust rule.
- Activation that ends in `conflict` → a redirect to Regras with the conflict banner.
- Stale state (for example, approving an already-approved item) → an inline "estado mudou"
  message and a refresh.

## Definition of Done / acceptance criteria

1. `tests/acceptance/increment-2` (176 assertions) and every Increment 1 acceptance test pass
   **unmodified** on real Supabase (CI) and on PGlite. `git diff <testspec-sha> --
   tests/acceptance` is empty.
2. The mutation proof is repeated against the real migration: each security or domain mutation
   below is caught.
3. `pnpm verify` is green locally and in CI, including authenticated E2E for the Brain flows.
4. The domain, security and UI reviews have no open BLOCKER, HIGH or MEDIUM findings.

## Tests

- **pgTAP acceptance (frozen):**
  - 200: isolation, internal-only, direct-write denial (50);
  - 210: strategy context (29);
  - 220: knowledge workflow (38);
  - 230: rules (59).
- **pgTAP builder** `040_client_brain`: constraints, grants, audit action names, recompute edge
  cases, idempotence.
- **Vitest:** zod schemas for the forms, error mapping, filter parsing.
- **Playwright:** the flows in "In scope", with the 404 boundary for a client user.

**Mutation proof (TEST_SPEC phase).** Run against a throwaway prototype migration, never
committed. Each mutation must turn at least one acceptance test red:

| Mutation | Description |
|---|---|
| M1 | open RLS on facts |
| M2 | client members read rules |
| M3 | untrusted facts approvable |
| M4 | silent learning (active on proposal) |
| M5 | item capability ignored |
| M6 | client capability ignored |
| M7 | no conflict detection |
| M8 | no scope/priority shadowing |
| M9 | validity ignored |
| M10 | supersession leaves the old rule active |
| M11 | `effective_rules` without access check |
| M12 | cross-client source accepted |
| M13 | untrusted rule activatable |
| M14 | direct INSERT granted |
| M15 | rejected/superseded rule re-activatable |
| M16 | approval not audited |

The Builder repeats this proof against the real migration.

## Observability / audit

`audit_logs` actions:
- `source.created`;
- `{fact,decision,insight}.{proposed,approved,rejected}`;
- `rule.{proposed,activated,superseded,rejected,conflict_detected,conflict_resolved}`;
- `{brand_profile,audience,offer,region}.saved`;
- `{audience,offer,region}.archived`.

Each entry has workspace, client, actor, target, and before/after status. Statements are not
copied into the audit (they may contain client-confidential text; the row itself is the record).

## Rollout / migration impact / rollback

Additive migration plus seed additions (local and CI only). Rollback: revert the web changes and
add a new migration dropping the new functions, tables and types. There is no production yet.

## Risks

- **Conflict semantics are deliberately narrow** (exact subject key). Near-duplicate subjects
  ("cta" vs "call-to-action") will not be detected. The UI should suggest existing subjects.
  Semantic detection is a later, human-confirmed AI proposal (Increment 4+).
- **Only admins approve and activate by default** (D1). Agencies must grant
  `knowledge.approve`/`rule.activate` explicitly. This is intentional (docs/05 §2).
- **Local verification gap** (no Docker): authenticated E2E runs only in CI.
- **Registry rate limit** (known debt): CI restarts are external failures.

## Decisions (reversible, Builder-level)

- **D1.** Strategy context saves are audited (cheap history, docs/10 "update history where
  necessary").
- **D2.** A source's `uri` is free text (no fetch, no validation beyond trimming). Sources are
  evidence, never instructions (docs/05 §4).
- **D3.** `effective_rules` returns `id, type, subject, statement, scope_type, channel, priority,
  effective_from, effective_until, source_id`. The TEST_SPEC freezes only `id` and `subject`.
- **D4.** The channel is a free lowercase key (`^[a-z0-9][a-z0-9_-]{0,39}$`). A Channel entity
  can replace it later without changing the contract.

## Architecture gate required?

`no`. The new entities come from docs/02 and docs/10. The capabilities and the role table are
unchanged. Approval semantics follow the four product decisions approved above. There are no new
trust boundaries (no external fetch, no AI), and the migration is additive.
