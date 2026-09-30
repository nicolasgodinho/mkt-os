# 00 — Product Constitution

## 1. Product definition

Jansen Marketing OS is an internal marketing operating system plus client portal. It combines operational work management, client/brand intelligence, content planning and approval, marketing analytics, and AI-assisted automation in one domain model.

It is **not** primarily a chatbot, generic project manager, generic DAM, generic CRM, or social scheduling clone. Those capabilities may exist, but they serve a single purpose: preserve and compound marketing context while reducing operational latency.

## 2. Product thesis

The system should automate work that consumes people so people can spend more time on strategy, creative judgment, relationship, taste and decision-making.

Technology has four jobs:

1. Move information without manual coordination.
2. Transform information into usable context and drafts.
3. Enforce repeatable quality/safety rules.
4. Preserve institutional learning so the next decision is better than the last.

Humans remain accountable for high-impact strategy, creative direction, relationship decisions and irreversible/reputational actions.

## 3. Experience surfaces

### 3.1 Jansen Internal OS

Desktop-first, dense, keyboard-friendly, high-throughput. Supports bulk actions, tables, boards, calendar, inspector panels, command palette and contextual AI.

### 3.2 Client Portal

Mobile-friendly, simplified and action-oriented. The first question is: **what needs the client's attention now?** It exposes approvals, requests, calendar, relevant content, files, meetings and results without exposing internal notes, margins, AI jobs or other clients.

### 3.3 Intelligence Layer

Cross-cutting, contextual and evidence-backed. AI appears as actions and suggestions inside the workflow, plus a transversal `Ask Jansen` interface. The UI must not center the product around an empty chat box.

## 4. Product principles

1. **One source of truth per concept.** Multiple views are allowed; duplicated domain truth is not.
2. **Context before generation.** Client Brain, source provenance and rules precede generative outputs.
3. **Evidence over magic scores.** Any score/recommendation must show factors/evidence.
4. **Human gates match risk.** Low-risk deterministic tasks can automate; reputational/irreversible tasks require stronger gates.
5. **Version what can change meaning.** Rules, content revisions, prompts, pipelines and critical strategy changes retain history.
6. **No silent learning.** AI cannot convert casual language into permanent brand truth without the appropriate validation path.
7. **Local-first AI, cloud-independent portal.** The customer experience remains available when the local GPU is offline.
8. **Fail safely.** Queue, integrations and AI jobs may fail without corrupting state or duplicating irreversible effects.
9. **Audit critical actions.** Publication, approvals, permission changes, rule activation, integration changes and destructive actions are traceable.
10. **Agents implement the product; they do not redefine it.** Architectural changes require explicit ADR/gate.

## 5. Classification of scope

### BLOCKER

- Workspace/client isolation + RLS.
- Immutable content revision and approval semantics.
- Separate operational model (`Project/Deliverable/Task`) from editorial model.
- Rule versioning/conflict semantics sufficient to avoid contradictory enforcement.
- AI job idempotency/recovery semantics.
- Trust boundary for external/RAG content.
- Protected acceptance tests/spec for autonomous coding.

### CORE

- Client Brain and structured knowledge.
- Goals + Initiatives.
- Opportunities, Pautas, Content, Revision, Asset, Publication.
- Requests, Projects, Deliverables, Tasks.
- Approvals, comments/threads.
- Calendar views.
- Google Drive connector.
- AI Worker + queue.
- Meeting → proposed knowledge.
- Search.
- Audit log for critical actions.
- Internal Home/Inbox and Client Portal essentials.

### LATER

- Full analytics connector suite.
- Auto-publishing to social networks.
- Advanced capacity planning.
- Dynamic image/video generation.
- Asset licensing/consent workflows.
- Social listening.
- Trend engine.
- Advanced experimentation/statistics.
- Feature flag platform beyond simple configuration.
- Rich incident console/observability platform.
- Fine-tuning/LoRA.

### IDEA

- External SaaS for other agencies.
- Fully autonomous campaign management.
- Cross-client anonymized benchmark product.

## 6. Decision/change control

This v1.0 specification is frozen for the first build. A change is considered architectural when it alters any of:

- entity ownership/relationships;
- tenant/client isolation;
- state machine meaning;
- approval semantics;
- permission boundaries;
- domain invariants;
- public API contract;
- event contract;
- destructive data migration behavior.

Architectural changes require an ADR under `docs/decisions/` and explicit human acceptance. Reversible implementation details do not.

## 7. Definition of build-ready

A feature is build-ready only when its ExecPlan defines:

- problem/goal;
- in-scope and non-goals;
- affected domain entities;
- allowed state transitions;
- permission requirements;
- UI surfaces;
- acceptance criteria;
- failure states;
- test cases;
- migration impact;
- observability/audit impact if relevant.
