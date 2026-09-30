# 04 — State Machines

State transitions are domain rules, not UI decoration.

## Content

`IDEA → BRIEF → READY → PRODUCING → INTERNAL_REVIEW → CLIENT_REVIEW → APPROVED → SCHEDULED → PUBLISHED → ANALYZED`

Optional/terminal: `CANCELED`, `ARCHIVED`.

Rules:
- `READY` requires Definition of Ready fields.
- `CLIENT_REVIEW` requires an immutable revision.
- `APPROVED` refers to an approved revision, not mutable Content payload.
- Material edit after approval creates a new revision and may transition back to review.
- `PUBLISHED` requires a Publication record with remote/local delivery state.

## ApprovalRequest

`DRAFT → REQUESTED → APPROVED | CHANGES_REQUESTED | CANCELED | EXPIRED`

An approval request references exactly one immutable `content_revision_id` or other versioned approvable resource.

## Request

`SUBMITTED → TRIAGE → ACCEPTED → PLANNED → IN_PROGRESS → CLIENT_ACTION? → DONE`

Alternative: `OUT_OF_SCOPE`, `REJECTED`, `CANCELED`.

## Initiative

`DRAFT → PLANNING → PRODUCTION → SCHEDULED → ACTIVE → COMPLETED`

Alternatives: `PAUSED`, `CANCELED`.

## Opportunity

`DETECTED → REVIEWED → WATCHING | DISMISSED | CONVERTED`

Converted Opportunity links to resulting Pauta.

## Rule

`PROPOSED → ACTIVE → SUPERSEDED`

Also `REJECTED`, `EXPIRED`, `CONFLICT`.

## AI Job

`QUEUED → LEASED/RUNNING → COMPLETED`

Failure paths: `RETRY_WAIT → QUEUED`, `FAILED`, `DEAD_LETTER`, `CANCELED`.

Job completion must be idempotent.

## Project

`PLANNED → ACTIVE → WAITING_CLIENT? → AT_RISK? → COMPLETED`

Alternatives: `PAUSED`, `CANCELED`.

## Publication

`DRAFT → SCHEDULED → PUBLISHING → PUBLISHED`

Failure: `FAILED → RETRYING | CANCELED`.

A Publication never modifies the approved revision to record delivery data.
