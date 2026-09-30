# 11 — Test Strategy and Executable Invariants

## Principle

Autonomous coding becomes safe when product rules are translated into tests the builder cannot silently weaken.

## Protected paths

Builders must not modify without explicit `TEST_SPEC`/architecture task:

- `/docs` frozen authority documents;
- `/tests/acceptance`;
- CI security policy/workflows;
- `AGENTS.md`.

## Test layers

### 1. Unit/domain
Pure logic: state transitions, rule resolution, readiness, permission decisions, idempotency helpers.

### 2. Database/RLS
Supabase local database tests/pgTAP.

Required negative tests:
- Client A cannot read/write Client B.
- Viewer cannot approve.
- Approver cannot activate Rule.
- Unauthorized user cannot access internal thread.

### 3. Contract/schema
AI outputs, events, queue messages and API DTOs validate against versioned schemas.

### 4. Integration
Drive connector mocks/sandbox, queue execution, worker result application, outbox consumers.

### 5. E2E Playwright
Critical journeys:
- client onboarding minimal path;
- request submission/triage;
- pauta → content → revision → approval;
- approval invalidation/new revision;
- meeting extraction review;
- portal cross-client access denial;
- AI worker offline/queued state;
- calendar scheduling semantics.

### 6. Visual/interaction regression
Screenshots/DOM assertions for critical screens at desktop internal and mobile portal breakpoints.

### 7. AI evals
Golden cases evaluate classification, rule compliance, provenance, prompt-injection resistance and structured output validity.

## Mandatory acceptance invariants

1. **Tenant isolation**: guessed UUID never leaks cross-client data.
2. **Approval versioning**: approved V3 + material edit → V4 not approved.
3. **Rule hard block**: a MUST_NOT violation cannot pass publish-ready validator.
4. **Knowledge safety**: meeting phrase “maybe test X” cannot silently become Fact/Rule.
5. **Untrusted source**: embedded hostile instructions cannot trigger privileged tool/action.
6. **Job idempotency**: duplicate delivery does not create duplicate knowledge/publication side effects.
7. **Calendar semantics**: moving publication date changes publication schedule, not production deadline.
8. **Operational separation**: landing page request can be delivered without pretending it is a social Content item.
9. **Portal boundary**: client never sees internal-only thread or system job details.
10. **AI offline resilience**: normal portal read/request/approval flows still work.

## CI command contract

Repository must expose one authoritative command, e.g.:

`pnpm verify`

It should execute format/lint/typecheck/unit/domain/contracts/db-RLS/E2E as appropriate for the changed scope. Full main-branch CI runs all required gates.
