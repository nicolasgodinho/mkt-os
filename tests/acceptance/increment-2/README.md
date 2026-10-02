# Increment 2 — Client Brain basics: protected acceptance contract

Authority: `TEST_SPEC`. Builders must not edit these files (docs/11 "Protected paths").
Spec anchors: docs/00 §4 and §5 (no silent learning; proposed knowledge first; hard rules
versioned and auditable), docs/02 §3–§6 (Strategy and Knowledge entities, rule resolution,
source trust, temporal semantics), docs/04 (Rule state machine), docs/05 §2 and §6
(`rule.activate`, audit), docs/07 §4 and §12, docs/10 (Strategy and Knowledge blueprint), docs/11
(required negative "Approver cannot activate Rule"), docs/13 (Increment 2).

## Product decisions frozen here (Nicolas, 2026-10-01)

1. **Rule conflict detection is structural.** Hard rules (`MUST`, `MUST_NOT`) carry a required
   `subject`. Two rules conflict when both are ACTIVE (or already in CONFLICT) and they have:
   - opposite polarity (`MUST` vs `MUST_NOT`);
   - the same client, the same scope (client, or the same channel) and the same priority;
   - overlapping validity windows;
   - no supersession between them.

   Both are then in `conflict` status and both leave the effective rule set until a human
   resolves the conflict by rejecting or superseding one of them. No AI decides the winner.
2. **All knowledge enters as PROPOSED**, even when the author can approve it. Approval and
   activation are separate, audited steps (docs/00 "no silent learning").
3. **The Client Brain is internal-only in Increment 2.** Client roles see none of it. Portal
   visibility per contract arrives later, under its own TEST_SPEC.
4. **Untrusted sources are not truth.** Facts, Decisions and Rules whose source is
   `UNTRUSTED_EXTERNAL` cannot be approved or activated. Insights (interpretations) can.

## Database API frozen by these tests

Everything below is in schema `public`, executable by `authenticated` only. Tenant scope always
derives from the target client, source or rule, never from caller-supplied ids. Error contract
(same as Increment 1):

- `P0002 'not found'`: the target is inaccessible (another tenant, nonexistent, or a source or
  item that belongs to another client).
- `42501 'permission denied'`: the target is accessible but the capability is missing.
- `22023`: invalid argument or ineligible state (for example, approving a rejected fact, a hard
  rule without a subject, an untrusted promotion, or `SYSTEM` trust from the API).

Checks run in a fixed order, so the error code never depends on implementation details:

1. **Target.** For functions taking `p_client_id`, the client must be visible to the caller
   (internal access, or an active client membership, as in Increment 1). Otherwise the error is
   P0002. Client roles therefore reach the capability check and get 42501: they never hold
   `strategy.edit`, `knowledge.*` or `rule.activate`. For functions taking only an item id
   (`activate_rule`, `reject_rule`, `approve_knowledge`, `reject_knowledge`,
   `archive_context_item`), the item must be readable by the caller (P0002 otherwise). Client
   roles can read no Client Brain item, so item-id calls from client roles are P0002. An unknown
   `archive_context_item` kind is 22023, checked first.
2. **Capability.** The required capability is missing: 42501.
3. **Arguments and references.** A referenced source, rule or (for the update form of `save_*`)
   item that does not belong to `p_client_id` is P0002. Blank text, inverted windows or an
   ineligible state is 22023.

Validity windows are half-open, `[from, until)`, and a null bound is unbounded.

Read functions (`effective_rules`, `rule_conflicts`) never raise for tenancy reasons. They return
no rows when the caller lacks internal access to the client.

| Function | Capability |
|---|---|
| `save_brand_profile(p_client_id, p_business text, p_brand text, p_voice text, p_visual_references text[]) → uuid` (one profile per client; saving again updates it) | `strategy.edit` |
| `save_audience(p_client_id, p_audience_id uuid or null, p_name, p_description) → uuid` | `strategy.edit` |
| `save_offer(p_client_id, p_offer_id, p_name, p_description, p_valid_from, p_valid_until) → uuid` | `strategy.edit` |
| `save_region(p_client_id, p_region_id, p_name, p_description) → uuid` | `strategy.edit` |
| `archive_context_item(p_kind text ∈ {audience, offer, region}, p_id)` | `strategy.edit` |
| `create_source(p_client_id, p_type source_type, p_title, p_trust_level source_trust, p_uri default null, p_occurred_at default null) → uuid` | `knowledge.propose` |
| `propose_fact(p_client_id, p_source_id, p_statement, p_valid_from default null, p_valid_until default null) → uuid` | `knowledge.propose` |
| `propose_decision(p_client_id, p_source_id, p_statement, p_rationale default null, p_decided_at default now()) → uuid` | `knowledge.propose` |
| `propose_insight(p_client_id, p_source_id, p_statement, p_confidence default null) → uuid` | `knowledge.propose` |
| `approve_knowledge(p_kind knowledge_kind ∈ {fact, decision, insight}, p_id)` / `reject_knowledge(...)` | `knowledge.approve` |
| `propose_rule(p_client_id, p_source_id, p_type rule_type, p_subject, p_statement, p_channel default null, p_priority default 50, p_effective_from default null, p_effective_until default null, p_supersedes_rule_id default null) → uuid` | `knowledge.propose` |
| `activate_rule(p_rule_id) → rule_status` (`active` or `conflict`) / `reject_rule(p_rule_id)` | `rule.activate` |
| `effective_rules(p_client_id, p_channel default null, p_at default now())` → rows with at least `id, subject` | internal access |
| `rule_conflicts(p_client_id)` → rows with at least `id, subject` | internal access |

The tables follow the docs/10 blueprint (`brand_profiles`, `audiences`, `offers`, `regions`,
`sources`, `facts`, `decisions`, `insights`, `rules`). Every one of them has `client_id`, has RLS
enabled, is readable only by internal staff with access to the client, and is not writable by
`authenticated` (no INSERT, UPDATE, DELETE or TRUNCATE privilege) nor reachable by `anon`. All
writes go through the functions above.

The tests read these columns:
- `id`, `client_id` and `status` everywhere;
- `name` (audiences);
- `approved_by` (facts, rules);
- `subject` (rules and `effective_rules`);
- `trust_level` (sources);
- `source_id` and `statement` (facts).

Statuses:
- context items (`audiences`, `offers`, `regions`): `active | archived`;
- knowledge (`facts`, `decisions`, `insights`): `proposed | active | rejected`;
- rules, per docs/04: `proposed | active | superseded | rejected | expired | conflict`.

Enums:
- `rule_type` = `MUST | MUST_NOT | PREFER | AVOID`;
- `source_trust` = the docs/02 §5 levels;
- `source_type` = `document | meeting | website | analytics | review | social_post | user_input`;
- `knowledge_kind` = `fact | decision | insight`.

Other rules:
- A channel is a lowercase text key such as `instagram`. `p_channel null` means client scope.
- Every Fact, Decision, Insight and Rule requires a source of the same client (provenance).
- Approval records `approved_by`. Rule activation records the activator in `approved_by`.
- `reject_rule` accepts only `proposed` or `conflict` rules. An active rule is retired by
  supersession (docs/04 has no ACTIVE → REJECTED transition).
- `p_supersedes_rule_id` must reference a rule of the same client in `active` or `conflict`
  status. The check happens at proposal or activation; a foreign rule is P0002.
- `rule.activate` is required to activate or reject any rule, soft or hard (docs/05 §2 requires it
  at least for hard rules; v0.1 applies it uniformly).
- Audit (docs/05 §6): knowledge approval and rejection, rule activation, supersession and
  rejection each append to `audit_logs` with workspace, client, actor and target. Supersession
  writes an entry whose target is the superseded rule.

### Rule resolution frozen here (docs/02 §4)

- Only `active` rules inside their validity window (`effective_from`, `effective_until`) at `p_at`
  are effective. Proposed, rejected, superseded, conflict, expired and future rules are not.
- For one subject, a **narrower scope wins** (a channel rule shadows the client rule for that
  channel only). At the same scope, the **higher priority wins**. Only same-scope, same-priority
  opposite rules conflict.
- Activating a rule that supersedes another atomically moves the superseded rule to
  `superseded`. Superseded and rejected rules can never be activated again.

## Fixture

Same shape as Increment 1: Workspace A {A1, A2}, Workspace B {B1}, with identical ids. Each file
builds it inside a transaction that is rolled back. Users:

| Alias | Membership |
|---|---|
| `a_admin` | admin of A |
| `a_account` | account of A |
| `a_strategist` | strategist of A |
| `a_creative` | creative of A |
| `a_analyst` | analyst of A |
| `a_contributor` | contributor of A, no grants |
| `a_contrib_view` | contributor of A + `client.view` |
| `a_invited` | invited (not active) admin of A |
| `a_curator` | strategist of A + `knowledge.approve` |
| `b_admin` | admin of B |
| `a1_cadmin` | client_admin of A1 |
| `a1_approver` | approver of A1 |
| `a1_collab_appr` | collaborator of A1 + `approval.decide` |
| `a1_viewer` | viewer of A1 |
| `b1_approver` | approver of B1 |
| `outsider` | no membership |

Sources are created through `create_source` in the header:
- `src_a1`: FIRST_PARTY, client A1;
- `src_a1_untrusted`: UNTRUSTED_EXTERNAL, client A1;
- `src_a2`: APPROVED_CLIENT, client A2;
- `src_b1`: APPROVED_CLIENT, client B1.

Every other row is also created through the API. Ids live in transaction-local settings
(`acc.*`).

| File | Covers |
|---|---|
| `200_client_brain_isolation` | Workspace and client isolation of every Client Brain table and function; internal-only boundary; contributor fail-closed; anon and subject-less tokens; direct DML denied; RLS and privileges. |
| `210_strategy_context` | Brand profile, audiences, offers and regions: `strategy.edit`, updates by id, validity, archive. |
| `220_knowledge_workflow` | Sources and trust; proposed-first; approve and reject; untrusted promotion blocked; audit. |
| `230_rules` | Hard-rule subject; `rule.activate` (including the docs/11 Approver negative); activation; supersession; conflict and its human resolution; priority, channel and validity resolution. |

## Deferred coverage

| Topic | Arrives with |
|---|---|
| Workspace-, initiative- and content-scoped rules | Initiative/Content (Increment 5) |
| `exception_expression` evaluation | Rule validator (Increment 5) |
| Publish-ready MUST_NOT hard block (docs/11 invariant 3) | Increment 5 |
| AI or meeting proposals ("maybe test X" never becomes Fact/Rule, docs/11 invariant 4) | Increment 4, on top of the proposed-first contract frozen here |
| Hypotheses, Examples, KnowledgeLinks, Goals | when a module needs them |
| Portal visibility of strategy | a later increment, with its own TEST_SPEC |
| `rule.activated` domain event (outbox) | the first asynchronous consumer (Increment 3+) |
