# 01 — Personas and Roles

## Internal personas

### Owner/Admin
Runs company/system configuration, integrations, access, clients and high-impact policy. Can see all workspace data.

### Account
Owns client relationship, requests, approvals, meetings and follow-up. Can view client strategy and operational work, but financial/system-admin capabilities can be restricted.

### Strategist
Owns marketing context, goals, initiatives, opportunities, pauta, research, insights and knowledge proposals.

### Creative
Works on briefs, content executions, assets, revisions and internal review.

### Analyst
Works on performance, analytics, experiments, evidence and insight proposals.

### Contributor
Task-scoped execution. Only sees clients/areas explicitly assigned.

## Client personas

### Client Admin
Manages client-side members, sees all client-portal areas allowed by contract, can be an approver.

### Approver
Can view assigned materials, comment, approve or request changes. Cannot alter Jansen internal strategy/rules directly.

### Collaborator
Can submit requests, comment and see allowed work, but cannot approve unless separately granted.

### Viewer
Read-only access to allowed client portal content.

## Capability model

Use role defaults plus explicit capabilities. Avoid a giant static permission matrix in v0.1.

Core capabilities:

- `workspace.manage`
- `client.manage`
- `client.view`
- `strategy.edit`
- `knowledge.propose`
- `knowledge.approve`
- `rule.activate`
- `content.create`
- `content.edit`
- `content.review_internal`
- `approval.request`
- `approval.decide`
- `publication.schedule`
- `publication.publish`
- `request.submit`
- `request.triage`
- `project.manage`
- `integration.manage`
- `audit.view`
- `admin.support`

## Visibility boundary

Internal comments, internal AI traces, margins/costs, unpublished strategic notes and other-client information are never exposed to client roles unless an explicit domain field is designed as client-visible.
