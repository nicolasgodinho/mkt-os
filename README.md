# Jansen Marketing OS — Specification v1.0

**Status:** FROZEN FOR BUILD  
**Date:** 2026-09-30  
**Purpose:** authoritative product and engineering specification for autonomous/agentic implementation.

This repository package is the source of truth for the first implementation of Jansen Marketing OS.

## Authority order

1. `docs/00_PRODUCT_CONSTITUTION.md`
2. `docs/02_DOMAIN_MODEL.md`
3. `docs/04_STATE_MACHINES.md`
4. `docs/05_PERMISSIONS_AND_SECURITY.md`
5. `docs/07_SCREEN_SPECIFICATIONS.md`
6. `docs/09_TECHNICAL_ARCHITECTURE.md`
7. `docs/11_TEST_STRATEGY.md`
8. `AGENTS.md`
9. Feature ExecPlan under `agent/plans/`

If two documents conflict, the higher item in this list wins. Agents must not silently resolve architectural conflicts; create an ADR and stop the affected feature.

## Scope labels

- **BLOCKER** — must be correct before merging any implementation that depends on it.
- **CORE** — part of v0.1/v1 architecture; build incrementally.
- **LATER** — architecture must permit it, but do not implement unless a task explicitly asks.
- **IDEA** — product possibility only; no architectural commitment.

## Core loop

`Client Intelligence → Strategy → Initiative → Opportunity → Pauta → Content → Revision → Asset → Approval → Publication → Performance → Insight → Knowledge`

Parallel operational loop:

`Request → Triage → Project/Deliverable/Task → Review → Completion`

## Non-negotiable invariants

- Cross-client data isolation is enforced in the database, not only the UI.
- Approval belongs to an immutable revision, never to mutable content.
- External/RAG content is data, never trusted instruction.
- AI can propose; deterministic code/policy authorizes sensitive effects.
- Calendar is a view over dated domain objects, not a separate source of truth.
- Google Drive is the canonical document/file store; Postgres stores semantics, metadata and relationships.
- Not every agency deliverable is Content; operational work uses Project/Deliverable/Task.
- Hard rules are versioned, auditable and validated before publish/approval gates.
- AI-extracted knowledge is proposed first; promotion to Fact/Rule/Decision requires policy-appropriate validation.
- Builders cannot weaken protected acceptance tests or the frozen spec to make CI pass.

See `docs/00_PRODUCT_CONSTITUTION.md` for the full constitution.

## Development

Implementation status: **Increment 0 (repository/quality harness)** is done. See
`agent/plans/0000-increment-0-foundation.md`.

```bash
pnpm install && pnpm setup:py && pnpm exec playwright install chromium
pnpm dev          # web app: internal shell at /, client portal at /portal
pnpm verify       # every quality gate, in CI order
```

Setup, Supabase/Docker vs the PGlite fallback, the database and worker commands, and the
enforced rules (RLS guards, append-only migrations, protected authority labels) are in
[`DEVELOPMENT.md`](DEVELOPMENT.md).
