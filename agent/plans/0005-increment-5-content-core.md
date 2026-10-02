# ExecPlan 0005 — Increment 5: Marketing/content core

**Status:** approved under Nicolas's standing instruction (2026-10-02). This plan runs autonomously. Its decisions are recorded here and in the TEST_SPEC README.

**Spec anchor:** docs/13 Increment 5: Initiative, Opportunity, Pauta, Content, immutable Revision, rule validator.

**Contract:** `tests/acceptance/increment-5/` (PR nicolasgodinho/mkt-os#19). Where the tests and this plan disagree, the tests win.

## Goal

Deliver the core of the v0.1 demo loop (docs/13, steps 9–12):

> opportunity → pauta with Definition of Ready → content → immutable revision → validation against the active hard rules → internal approval of an exact revision.

This builds the foundation that Increment 6 (client approval) and Increment 7 (scheduling) attach to.

## Decisions

The README freezes these decisions:
1. Capabilities follow the existing default table: `strategy.edit`, `content.create`, `content.edit`, `content.review_internal`.
2. The Definition of Ready has 4 items. Content can only start from a ready pauta.
3. Revisions are immutable through a trigger.
4. Approval targets a revision. Editing the content afterwards never changes the approved revision.
5. The rule validator is deterministic and checked by a person. A rule is blocking when its check is missing, when it is violated, or when it has an open conflict.
6. Everything is internal-only until Increment 6.

## In scope

- **Migration `20261002160000_content_core.sql`.** This is the prototype the TEST_SPEC proved.
- **Builder pgTAP `070_content_core`:**
  - payload validation;
  - hash determinism;
  - audit action names;
  - helper privileges;
  - initiative and opportunity edge cases.
- **Web, in the client context.** One "Conteúdo" hub at `/w/[ws]/clients/[id]/content`, with these tabs:
  - **Pautas:** list, create, and pauta detail with the Definition of Ready checklist, fields, mark ready, and its contents.
  - **Oportunidades:** inbox with watch, dismiss and convert.
  - **Iniciativas:** list, create, and status.
- **Content Studio** (`.../content/[contentId]`):
  - working payload editor and preview;
  - revision history;
  - rule validation summary with per-rule checks;
  - submit for review; approve or request changes;
  - linked pauta and initiative.
- **Seed.** A ready pauta, plus one approved content and one content in review for Cliente Demo A.
- **Tests:**
  - Vitest for the payload and DoR helpers.
  - E2E: a strategist creates a pauta and marks it ready; a creative writes, submits and checks the rules. A MUST_NOT violation blocks approval; a pass approves. Editing after approval keeps the approved revision. A client user gets a 404.

## Non-goals (deferred)

| Item | Destination |
|---|---|
| Client review and approval requests | Increment 6 |
| Publication schedule | Increment 7 |
| AI-generated opportunities, drafts and semantic rule suggestions | Later, as proposals only |
| Assets | Increment 8 |
| Goals linked to initiatives (`goal_ids`) | When Goals exist |

## Security

- **Writes:** everything is client-scoped and goes through SECURITY DEFINER functions.
- **References:** all references (audiences, offers, sources, initiatives, pautas) are checked against the same client.
- **Revisions:** they are immutable even for the database owner.
- **Validator inputs:** it reads `effective_rules` and the open conflicts with the caller's internal access.

## Architecture gate

**No.** The entities come from docs/02 and docs/10. The capabilities and roles are unchanged, and there is no new trust boundary.
