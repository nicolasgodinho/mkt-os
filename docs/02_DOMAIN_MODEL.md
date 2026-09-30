# 02 — Domain Model

## 1. Bounded contexts

### Identity
`Workspace`, `User`, `WorkspaceMembership`, `Client`, `ClientMembership`

### Commercial (LATER, but modeled)
`ProspectAccount`, `ProspectAudit`

### Strategy
`Goal`, `Initiative`, `Audience`, `Offer`, `Region`, `BrandProfile`

### Knowledge
`Source`, `Fact`, `Decision`, `Rule`, `Insight`, `Hypothesis`, `Example`, `KnowledgeLink`

### Operations
`ServicePlan`, `ScopeEntitlement`, `Request`, `Project`, `Deliverable`, `Task`, `ChangeRequest`

### Content
`Opportunity`, `Pauta`, `Content`, `ContentRevision`, `Asset`, `Publication`

### Collaboration
`Meeting`, `Thread`, `Comment`, `ApprovalRequest`, `ApprovalDecision`, `Notification`

### Platform
`FileRecord`, `IntegrationConnection`, `DomainEvent`, `OutboxRecord`, `Job`, `AuditLog`, `SearchDocument`

## 2. Key relationships

```text
Workspace
 ├─ Users via WorkspaceMembership
 ├─ ProspectAccounts (LATER) -> convert to Client
 └─ Clients
     ├─ ClientMemberships
     ├─ BrandProfile / Audience / Offers / Regions
     ├─ Goals
     ├─ Initiatives
     │   ├─ Opportunities
     │   │   └─ Pautas
     │   │       └─ Content
     │   │           ├─ ContentRevisions
     │   │           │   └─ ApprovalRequests
     │   │           ├─ Assets
     │   │           └─ Publications
     │   └─ Projects/Deliverables (when campaign work is operational)
     ├─ ServicePlan / ScopeEntitlements
     ├─ Requests → scope check → Project/Deliverable/Task or ChangeRequest
     ├─ Knowledge objects
     ├─ Files (Drive-backed metadata)
     └─ Meetings → Source/transcript/knowledge proposals
```

## 3. Entity semantics


### ProspectAccount (LATER)
Pre-client company/account used for public research, prospect audit and commercial conversion. Conversion creates a Client while preserving linked research sources; it is not required for v0.1.

### ServicePlan / ScopeEntitlement
Machine-readable representation of what the current client agreement includes. It exists so Request triage can distinguish included work from out-of-scope work without reading a PDF manually every time. `ServicePlan` is the active agreement profile; `ScopeEntitlement` expresses service/type, quantity or limit, period, SLA/revisions and optional exceptions.

### Meeting
First-class collaboration/intelligence object with date, participants, recording/file source, transcript state and processing state. The transcript/document remains a `Source`; Meeting provides the operational lifecycle and UI anchor.

### Initiative
Unifies campaign/always-on/launch/activation without duplicating domain logic.

Required: `client_id`, `kind`, `name`, `status`, `start_at?`, `end_at?`, `goal_ids[]`.

`kind`: `campaign | always_on | launch | activation`.

### Opportunity
A detected/suggested reason to act. It is not yet editorial commitment.

Fields: `type`, `title`, `reason`, `evidence_refs`, `score_components`, `confidence`, `expires_at?`, `status`.

### Pauta
Approved editorial idea/angle. Captures `objective`, `audience`, `pillar`, `message`, `angle`, `cta`, `offer`, `sources`, `mandatories`, `constraints`.

### Content
Channel/format execution of a Pauta. Content is mutable as a work item, but approval targets immutable `ContentRevision` snapshots.

### ContentRevision — BLOCKER
Immutable snapshot of content payload at a point in time. A material edit after approval creates a new revision. Never mutate the approved revision.

### Asset
Media/file used or produced. Physical bytes remain in Google Drive when appropriate; database holds semantics and Drive file/revision identifiers.

### Publication
A distribution instance of Content to a channel/profile/date. One Content can have many Publications.

### Request
Client/internal intake item. It is not automatically a Task. It must pass triage/scope/capacity/planning.

### Project / Deliverable / Task
Operational execution model for non-editorial and mixed work such as websites, branding, landing pages, integrations, recordings and campaign production.

### Source
Origin of evidence/context: document, meeting, website, analytics dataset, review, social post, user input, etc. Includes provenance and trust level.

### Fact
Confirmed contextual statement with source and optional validity interval.

### Decision
Recorded choice with source, owner and rationale.

### Rule
Versioned instruction/policy. Types: `MUST`, `MUST_NOT`, `PREFER`, `AVOID`. Includes scope, priority, validity, exceptions and supersession.

### Insight
Interpretation supported by evidence; not automatically a Rule.

### Hypothesis
Testable proposition; explicitly not treated as fact.

### Example
Approved/rejected/high-performing/low-performing exemplar used as context.

## 4. Rule resolution

Rule scope specificity, from broad to narrow:

`workspace → client → channel → initiative → content/template`

Rules include `priority`, `effective_from`, `effective_until`, `exception_expression?`, `supersedes_rule_id?`.

If two active hard rules at the same effective specificity/priority conflict and no supersession/exception resolves them, mark `RULE_CONFLICT`. Do not let the LLM decide which one wins.

## 5. Trust levels for Sources

`SYSTEM | APPROVED_CLIENT | FIRST_PARTY | TRUSTED_EXTERNAL | UNTRUSTED_EXTERNAL`

Trust controls what downstream promotion is allowed. External source text never becomes tool/system instruction. RAG passages are quoted/structured as evidence, not appended as privileged prompt directives.

## 6. Temporal semantics

Facts, offers, prices, promotions, rules and external claims may have `valid_from` / `valid_until`. Generation and scheduling must detect expired/future-invalid context where relevant.

## 7. Shared base fields

Most entities carry:

`id`, `workspace_id`, `client_id?`, `created_at`, `updated_at`, `created_by`, `status`, optional `owner_id`.

Critical entities also carry version/audit references.


## 8. LATER extension contracts

These are intentionally not required for v0.1 migrations, but module boundaries reserve them so future intelligence does not distort Content/Knowledge:

- `Signal`: normalized observation from trend/search/review/social/competitor/performance sources.
- `MetricDefinition` / `MetricObservation`: normalized measurement model for channel/campaign/content performance.
- `Experiment`: hypothesis, variants, metric and result/evidence.
- `ResearchArtifact`: versioned audit/research output with evidence links.
- `BrandTokenSet` / `ContentTemplate`: executable brand/template inputs for deterministic post rendering.

These LATER objects may create Opportunities or Insights; they do not bypass Rules/Approval policies.
