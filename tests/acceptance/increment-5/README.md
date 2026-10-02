# Increment 5: marketing and content core (protected acceptance contract)

**Authority:** `TEST_SPEC`. Builders must not edit these files (docs/11 "Protected paths").

**Spec anchors:**
- docs/13 Increment 5: Initiative, Opportunity, Pauta, Content, immutable Revision, rule validator.
- docs/02: Initiative, Opportunity, Pauta, Content, ContentRevision (**BLOCKER**).
- docs/04: Content, Initiative and Opportunity state machines.
- docs/07 §6–§8: Opportunity Inbox, Pauta Detail, Content Studio.
- docs/10: Content tables.
- docs/11 invariants:
  - 2 (approval versioning; the part about internal approval is covered here);
  - 3 (rule hard block);
  - 1 and 9 (isolation).

## Decisions frozen here

These were taken autonomously under Nicolas's standing instruction of 2026-10-02. They are recorded in ExecPlan 0005.

1. **Capabilities** (no new capability):

   | Action | Capability |
   |---|---|
   | Initiatives, opportunities, pautas | `strategy.edit` |
   | Creating content | `content.create` |
   | Editing payload, submitting revisions | `content.edit` |
   | Rule checks, internal approval or changes | `content.review_internal` |

   Under the default table (D1), a strategist plans and creates content, and a creative edits and reviews it.
2. **Definition of Ready.** A pauta is ready only when it has all four checklist items: `objective`, at least one `audience`, a `message` *or* an `angle`, and a `cta`. Content can only execute a **ready** pauta, and starts in `ready`. An edit that breaks the Definition of Ready returns the pauta to `draft`.
3. **ContentRevision is immutable for everyone**, including the database owner. A trigger refuses UPDATE, DELETE and TRUNCATE. Submitting snapshots the working payload into revision *n+1*, with a hash.
4. **Approval targets a revision.** Internal approval sets `approved_revision_id`. After that, editing the working payload returns the content to `producing` and **never** touches the approved revision.
5. **Rule validator (docs/11 invariant 3).** It is deterministic and human-checked:
   - The revision under internal review is validated against the **effective hard rules** (MUST/MUST_NOT) of its client and channel, plus every **open rule conflict** that touches the client scope or that channel.
   - A rule is **blocking** if it has no check yet, if its check is `violation`, or if it is in conflict.
   - Internal approval is impossible while anything blocks.
   - Soft rules never block.
   - An AI semantic check (`rules.semantic_check.v1`, docs/08 §7) may later *suggest* checks. It never decides them.
6. **Client review is out of scope here.** Client review and approval requests arrive in Increment 6. Until then, everything here is internal-only (client roles see nothing).

## Database API frozen by these tests

All functions are in `public` and executable by `authenticated` only. They follow the same error contract and the same order of checks as earlier increments: P0002 when the target is not visible, then 42501 when a capability is missing, then 22023 for an invalid argument or state.

| Function | Rule |
|---|---|
| `create_initiative(p_client_id, p_kind initiative_kind, p_name, p_start_at date default null, p_end_at date default null) → uuid` | status `draft`; end ≥ start |
| `set_initiative_status(p_initiative_id, p_status initiative_status)` | docs/04: draft→planning; planning→production; production→scheduled; scheduled→active; active→completed. `paused` can be reached from those states and resumed. `canceled` is terminal. Any other transition is 22023. |
| `create_opportunity(p_client_id, p_type text, p_title, p_reason, p_initiative_id default null, p_confidence default null, p_expires_at default null, p_evidence_refs uuid[] default '{}') → uuid` | status `detected`; evidence must be sources of the same client (otherwise P0002) |
| `review_opportunity(p_opportunity_id, p_decision text)` | `watch` → `watching`; `dismiss` → `dismissed`; anything else is 22023 |
| `convert_opportunity(p_opportunity_id, p_title default null) → uuid` | Creates a draft pauta linked by `opportunity_id`; the opportunity becomes `converted`. Allowed once, and never from `dismissed`. |
| `create_pauta(p_client_id, p_title, p_initiative_id default null) → uuid` | status `draft` |
| `update_pauta(p_pauta_id, p_fields jsonb)` | Keys: `title, objective, audience_ids, pillar, angle, message, cta, offer_id, source_ids, mandatories, constraints`. Unknown keys are 22023. Referenced ids must belong to the same client (otherwise P0002). |
| `pauta_readiness(p_pauta_id)` | Rows `(field, ok)` for the four Definition of Ready items |
| `mark_pauta_ready(p_pauta_id)` | draft → ready; 22023 unless every Definition of Ready item is met |
| `create_content(p_pauta_id, p_channel, p_format, p_title) → uuid` | The pauta must be ready; status `ready` |
| `save_content_payload(p_content_id, p_payload jsonb)` | Keys: `headline, body, cta, hashtags (string[]), alt_text`; unknown keys are 22023. Status becomes `producing`. |
| `submit_for_internal_review(p_content_id) → uuid` | Needs a non-blank `body`. Creates revision *n+1* and moves to `internal_review`. |
| `record_rule_check(p_revision_id, p_rule_id, p_result rule_check_result, p_note default null)` | `pass`, `violation` or `not_applicable`. Only for the hard rules of the revision under review; a rule of another client is P0002. |
| `revision_validation(p_revision_id)` | Rows `(rule_id, type, subject, statement, result, blocking)`; no rows without internal access |
| `complete_internal_review(p_revision_id, p_decision text, p_note default null)` | `approve` (22023 while anything blocks) → `approved` at that revision; `changes` → `producing`. Only for the current revision under review. |

**Columns read by the tests:**
- `initiatives`: `kind`, `status`, `client_id`;
- `opportunities`: `status`;
- `pautas`: `status`, `title`, `opportunity_id`;
- `contents`: `status`, `channel`, `pauta_id`, `current_revision_id`, `approved_revision_id`;
- `content_revisions`: `revision_number`, `payload`, `immutable_hash`.

**Audit.** Every write is audited. The tests check pauta changes, rule checks and the internal approval of a revision.

## Fixture

- **Workspaces:** Workspace A {A1, A2} and Workspace B {B1}, with the same ids as in earlier increments.
- **Users:**
  - workspace A: `a_admin`, `a_account` (no content capabilities), `a_strategist`, `a_creative`, `a_contributor`;
  - workspace B: `b_admin`;
  - client A1: `a1_cadmin`, `a1_approver`.
- **Client Brain data,** created through the Increment 2 API:
  - Sources, audience and offer in A1. Rules in A1:
    - MUST `cta` (client scope);
    - MUST_NOT `preco` (client scope);
    - a soft PREFER;
    - MUST_NOT `emoji` (Instagram only).
  - Source and audience in A2.
  - Source and pauta in B1.

## Deferred coverage

| Topic | Arrives with |
|---|---|
| Client review, approval requests, invalidation of old approvals | Increment 6 |
| Scheduling and publications | Increment 7 |
| AI opportunity generation, AI content drafts, AI semantic rule suggestions | Later, as proposals only (docs/08 §7, §8) |
| Assets and Drive files | Increment 8 |
| Workspace-, initiative- and content-scoped rules; `exception_expression` | Later (the rule validator works on client and channel scope) |
