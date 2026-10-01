# ADR 0002 — Contributor client access stays fail-closed until v0.2

- **Status:** accepted
- **Date:** 2026-10-01
- **Scope:** authorization of the internal `contributor` role. No entity, relationship or
  approval semantics change.
- **Requires:** `authority:ARCHITECTURE_CHANGE` (this file lives under `/docs`).

## Context

`docs/01_PERSONAS_AND_ROLES.md` describes the Contributor as "task-scoped execution. Only sees
clients/areas explicitly assigned." The domain model (`docs/02`, `docs/10`) has no entity that
assigns an internal user to a specific client:

- `ClientMembership` models the client-side personas (Client Admin, Approver, Collaborator, Viewer).
  Reusing it for internal staff would blur the internal/external boundary that `docs/05` and the
  portal depend on.
- `Task` (`assignee_id`) belongs to the operational model (`Project/Deliverable/Task`), which is
  scheduled for v0.2 (`docs/13`, `docs/14`).

Increment 1 (ExecPlan 0001, PR #5) therefore implemented the Contributor **fail-closed**:

- no default capabilities, so no client is visible;
- an admin may grant an explicit capability (for example `client.view`), which is workspace-wide,
  under the "role defaults + explicit capabilities" model of `docs/01`.

The protected acceptance tests (`tests/acceptance/increment-1`) freeze this behavior.

## Decision

1. Keep Contributor access **fail-closed**. Do not create a `ClientAssignment` entity. Do not add
   an internal role to `ClientMembership`.
2. Effective per-client (and per-area) assignment for contributors will be designed with the
   operational model (`Project/Deliverable/Task`) in **v0.2**. A contributor's reach will then
   derive from the work explicitly assigned to them, which matches "task-scoped execution".
3. Until then, an admin who needs a contributor on client work grants an explicit capability
   (workspace-wide) or uses a different internal role, knowing it is broader than per-client
   assignment.

## Consequences

- No schema or authorization change now. Increment 1 behavior and tests stay as they are.
- Contributors are not useful for client work in v0.1 without an explicit workspace-wide grant.
  This is acceptable: the v0.1 demo path (`docs/13`) does not need contributors.
- The v0.2 ExecPlan for Project/Deliverable/Task must include contributor scoping. It must keep
  isolation enforced in the database (RLS), never only in the UI. Its acceptance tests need a
  `TEST_SPEC` task.

## Alternatives considered

- **New `ClientAssignment` entity.** Rejected for now: it is a new domain entity without a spec
  anchor, and v0.2 work assignment will likely subsume it.
- **Internal role on `ClientMembership`.** Rejected: it mixes internal staff with client-side
  personas in one relation and risks internal users being treated as portal members, or the
  reverse.
- **Workspace-wide access for contributors by default.** Rejected: it contradicts docs/01 ("only
  sees clients/areas explicitly assigned").

## Migration / backward compatibility

None. This records the behavior already shipped in `b051f33`.

## Approval

Accepted on 2026-10-01 by Nicolas Godinho (repository owner), with Increment 1 approval and the
confirmation of the default capability table (ExecPlan 0001 decision D1).
