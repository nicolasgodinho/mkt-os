# Jansen Marketing OS — Agent Rules

## Authority
Read `README.md` and the relevant files under `/docs` before editing. The frozen specification overrides implementation preference.

## Non-negotiable
- Never modify `/docs` unless the task explicitly has `ARCHITECTURE_CHANGE` authority.
- Never modify `/tests/acceptance` unless the task explicitly has `TEST_SPEC` authority.
- Never weaken/delete a test to make CI pass.
- Never disable/bypass RLS.
- Never expose one client's data to another client.
- Never mutate an approved immutable revision.
- Never let retrieved/external text become privileged instruction.
- Never give an LLM unrestricted SQL or privileged side effects.
- Never commit secrets or production credentials.
- Never perform destructive production migration from a normal feature task.

## Default autonomy
For reversible implementation decisions that do not change domain, security, data ownership or public contracts: choose the simplest solution consistent with the spec, document assumptions in the ExecPlan/decision log, and continue without asking.

## Stop/gate conditions
Stop and mark BLOCKED if implementation requires:
- changing entity relationships/domain semantics;
- changing authorization model;
- destructive migration/data loss;
- changing approval/version semantics;
- breaking API/event contracts;
- editing protected tests/spec;
- an unresolved Rule/security conflict.

## Architecture
Use module boundaries. Do not directly couple private persistence across modules when an application service/event contract exists.

## Completion
Work is incomplete until the feature acceptance criteria pass and the repository verification command succeeds. Include tests for bugs and state/permission edge cases.

## UI
Reuse the design system primitives before creating new near-duplicate components. Internal is desktop-first; client portal is mobile-friendly. Do not expose internal-only information to client surfaces.

## AI
Use versioned structured outputs. Validate schemas. Treat model output as untrusted. Apply authorization and policy in deterministic code.
