# 06 — Information Architecture

## Internal global navigation

- Home
- Inbox
- Clients
- Calendar
- Campaigns / Initiatives
- Content
- Approvals
- Requests
- Intelligence
- Analytics
- Assets
- Automations
- Settings

## Client context navigation

- Overview
- Strategy
- Calendar
- Initiatives
- Content
- Approvals
- Requests
- Intelligence
- Analytics
- Assets
- Knowledge
- Meetings

## Client Portal navigation

- Home
- Calendar
- Approvals
- Requests
- Content
- Results
- Files
- Meetings

Optional strategy visibility is contract/config dependent.

## View philosophy

Table, Board, Calendar and Timeline are views over the same domain records. They must not create duplicate records simply to appear in a different view.

## Page interaction pattern

Internal UI uses:

`Sidebar + Workspace + contextual Inspector`

Clicking an entity from a list/calendar should normally open a peek/inspector first. Deep work can open the entity full page. This preserves context and reduces navigation churn.

## Calendar model

Calendar is a projection of typed dated events, such as:
- publication schedule;
- production deadline;
- review/approval deadline;
- initiative milestone;
- meeting;
- recording;
- seasonal/external event.

Dragging an item must have explicit semantics for which date field is changed.

## Inbox model

Inbox contains actionable items, not every notification:
- approvals needed;
- client requests;
- mentions;
- missing info;
- overdue work;
- AI knowledge proposals;
- integration/automation failures requiring human action;
- significant performance signals.

Informational updates belong in notification/activity feeds or digests.
