# 07 — Critical Screen Specifications

These screens define v0.1 UX behavior. Pixel-perfect styling is not frozen; hierarchy and required behavior are.

## 1. Internal Home / Inbox

Purpose: answer “what needs attention today?”

Required:
- Needs Attention list grouped/severity-sorted.
- Today schedule.
- Pending approvals/requests.
- AI knowledge proposals count.
- High-signal opportunities/alerts.
- Quick actions.

Must not become an analytics dashboard full of vanity charts.

## 2. Clients List

Table/list with client status, owner, brain/setup health, pending client actions, current initiatives and integration health summary.

## 3. Client Overview

Required:
- identity/status;
- current goals/initiatives;
- upcoming calendar;
- open requests/approvals;
- recent insights;
- Client Brain completeness/context quality;
- integration health.

## 4. Client Brain / Strategy

Sections: Business, Brand, Audience, Offers, Regions, Voice/Visual references, Goals, Rules, Knowledge.

Facts/Rules show provenance and current status. Proposed knowledge is visually distinct from active knowledge.

## 5. Calendar

Views: Month, Week, List; optional Board elsewhere.

Filters: Client, Channel, Initiative, Status, Event Type.

Supports unscheduled backlog drawer and typed drag/drop semantics.

## 6. Opportunity Inbox

Card/list fields: title, signal type, why it matters, client, evidence, confidence, expiry/timeliness, score components.

Actions: Convert to Pauta, Watch, Dismiss.

## 7. Pauta Detail

Required:
- WHY THIS EXISTS/evidence;
- objective;
- audience;
- pillar;
- message/angle;
- offer/CTA;
- sources;
- mandatory/forbidden context;
- Definition of Ready checklist;
- executions (Content items).

## 8. Content Studio

Required:
- preview;
- editable working payload;
- revisions/version history;
- comments;
- active rule validation summary;
- linked Pauta/Initiative;
- owner/status/dates;
- request internal/client review actions.

Approval always shows the exact revision under review.

## 9. Approvals

Tabs/filters: Awaiting me, Awaiting client, Changes requested, Approved.

Supports batch approval only where policy permits. Shows revision, due date, content preview and comments.

## 10. Request Intake + Triage

Client form changes fields by request type. Internal triage evaluates the active ServicePlan/ScopeEntitlements and shows scope result, requested date, urgency reason, missing info and actions: accept, out-of-scope/change request, reject, request info.

Client urgency is input, not final priority.

## 11. Meeting Intelligence Review

Anchored to a first-class Meeting record (participants/date/recording/transcript status). Shows transcript/source plus proposed structured objects:
- Fact;
- Decision;
- Rule;
- Insight;
- Task/question.

Each proposal supports Approve/Edit/Reject. Confidence and supporting transcript snippet/time reference shown where possible.

## 12. Knowledge / Rules

Search/filter by type, scope, status, source and validity. Rule conflicts are prominent and block affected automated flows.

## 13. Initiative Overview

Overview, Timeline, Content, Deliverables, Assets, Performance.

Shows objective, goals/KPIs, period, audience, offer/message, channels, milestones and execution status.

## 14. Client Portal Home

Mobile-first hierarchy:
1. “Needs you” actions.
2. Next 7 days.
3. Current initiatives/work.
4. Recent result/insight.

Never expose internal notes, margin/cost, agent traces or other clients.

## 15. Client Approval Screen

Large preview, exact revision, caption/copy/metadata, contextual comments, Approve and Request Changes. If a newer revision exists, old approval request is visibly stale/canceled.

## 16. Client Request Screen

Simple form with request category, objective/context, desired date, attachments and dynamic required questions. Shows SLA/status after submission.

## UI system patterns

Base components:
`AppShell`, `Sidebar`, `ContextSwitcher`, `PageHeader`, `Inspector`, `DataTable`, `Board`, `Calendar`, `Timeline`, `StatusBadge`, `EntityLink`, `CommandMenu`, `GlobalSearch`, `ActivityFeed`, `CommentThread`, `ApprovalBar`, `AssetPreview`, `EmptyState`, `AIPanel`, `JobProgress`.

Agents must reuse these before creating near-duplicate primitives.
