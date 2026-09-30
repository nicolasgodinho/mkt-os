# 12 — Autonomous Build Protocol (Claude/Codex)

## Goal

Allow coding agents to work for long stretches without continuous human supervision while preventing them from redefining the product, weakening tests or making unsafe production changes.

## Workflow

```text
Feature Spec
   ↓
ExecPlan
   ↓
Acceptance test design / protected tests
   ↓
Builder in isolated branch/worktree
   ↓
verify loop
   ↓
Parallel read-only review (domain/security/UI)
   ↓
Fixer
   ↓
verify
   ↓
Integrator
   ↓
preview/staging
   ↓
merge/release gate
```

## Agent roles

### Planner
Reads frozen docs; produces an ExecPlan. Does not implement.

### Test Designer
Creates/updates acceptance tests when task explicitly allows it. After freeze, builder cannot edit them.

### Builder
Implements feature. May make reversible implementation choices consistent with spec without asking.

### Domain Reviewer
Read-only review against domain model, invariants and state machines.

### Security Reviewer
Read-only review for RLS/authz/trust boundaries/secrets/unsafe agent side effects.

### UI Reviewer
Read-only browser/Playwright review against screen spec and design primitives.

### Fixer
Receives consolidated findings and fixes implementation.

### Integrator
Owns merging worktrees/branches and integration-level verification. Individual builders do not independently merge to protected main.

## Autonomy policy

Agents may decide without human input:
- reversible internal implementation detail;
- component composition within the design system;
- refactor preserving contracts;
- unit tests supporting frozen behavior;
- additive migration compatible with schema/domain;
- bug fix with unambiguous failing test.

Human/architecture gate required for:
- entity relationship/domain changes;
- permission/auth model changes;
- destructive migration/data loss;
- change to approval semantics;
- public API/event contract breaking change;
- production secrets/security policy;
- weakening/deleting acceptance tests;
- changing frozen spec.

## Failure/retry policy

Agent gets bounded repair iterations. If the same failure persists or fix requires architectural reinterpretation, mark `BLOCKED` and produce a concise diagnostic rather than looping indefinitely.

## Protected authority

The builder cannot modify `/docs`, `/tests/acceptance`, `AGENTS.md` or production deployment policies to make implementation pass.

## Worktree ownership

Parallel write-heavy agents work only on clearly separate modules/worktrees. Reviews/research/tests may parallelize more aggressively.

Suggested early split:
- identity/RLS/core;
- UI/design system;
- AI worker/contracts;
- Drive integration;
- content domain.

## Completion report

Every autonomous feature run ends with:
- files changed;
- migrations;
- tests run/pass/fail;
- acceptance criteria status;
- reviewer findings/resolution;
- screenshots/trace links when UI changed;
- assumptions/ADRs;
- remaining known risks.

## Tool compatibility

The protocol is tool-agnostic. It is compatible with non-interactive agent execution such as OpenAI Codex workflows and Claude Code print/headless/background modes, but repository contracts are authoritative over tool-specific defaults.
