# Increment 7: calendar and publication (protected acceptance contract)

**Authority:** `TEST_SPEC`. Builders must not edit these files (docs/11 "Protected paths").

**Spec anchors:**
- docs/13 Increment 7: typed calendar projection, publication schedule, internal and portal calendar views.
- docs/02 Publication; docs/04 Content and Publication state machines.
- docs/06 "Calendar model"; docs/07 §5 (Calendar) and §14 (Client Portal Home, "next 7 days").
- docs/10 `publications`.
- docs/11 invariants 2 (approval versioning), 7 (calendar semantics) and 9 (portal boundary).

These tests build on the Increment 5 and 6 APIs. Their fixture creates client-approved content through them.

## Decisions frozen here

They were taken autonomously under Nicolas's standing instruction of 2026-10-02 and are recorded in ExecPlan 0007.

1. **What can be scheduled.** Only content whose **current internally approved revision was approved by the client** (`client_approved_revision_id = approved_revision_id`). The content is `approved`, `scheduled` or `published`.
   - Scheduling requires `publication.schedule`.
   - The publication pins that revision and takes the content's channel unless another valid channel is given.
   - One content can have several publications.
   - The first publication moves the content from `approved` to `scheduled`.
   - The date must be in the future.
2. **Changing the schedule.** Rescheduling and canceling require `publication.schedule` and work only on `scheduled` publications.
   - Rescheduling changes only `publications.scheduled_at`.
   - Canceling the last scheduled publication returns the content to `approved`.
3. **Recording a publication.** v0.1 has no production social publishing (docs/13): a person records it.
   - It requires `publication.publish`.
   - It sets `published`, `published_at` and an optional `http(s)` link, and moves the content to `published`.
   - It never touches the revision or the client approval.
4. **Production deadline.** `contents.production_due_at` is set with `content.edit`. It never moves a publication, and moving a publication never moves it (invariant 7).
5. **Typed calendar.** `calendar_events` projects four event types. Each event names the one date field a move changes:

   | Event | Source | `date_field` | Who sees it |
   |---|---|---|---|
   | `publication` | `publications.scheduled_at` (not canceled) | `scheduled_at` | internal staff; client members see scheduled, publishing and published |
   | `production_deadline` | `contents.production_due_at` | `production_due_at` | internal staff only |
   | `approval_deadline` | open `approval_requests.due_at` | `due_at` | internal staff and client members |
   | `meeting` | `meetings.starts_at` | `starts_at` | internal staff only |

6. **What clients see.** Publications of their own client that are scheduled, publishing or published, and the calendar events above. Production deadlines, meetings and canceled publications stay internal.
7. **Scheduled content is frozen.** Editing a `scheduled` content is refused (the Increment 5 rule). To change it, cancel its publications first; the edit then needs a new internal and client approval before scheduling again.

## Database API frozen by these tests

All of it lives in `public` and is executable by `authenticated` only. Errors follow the same contract as before: P0002 when the target is not visible, then 42501, then 22023.

| Function | Rule |
|---|---|
| `schedule_publication(p_content_id, p_scheduled_at timestamptz, p_channel text default null) → uuid` | Decision 1. |
| `reschedule_publication(p_publication_id, p_scheduled_at timestamptz)` | Decision 2. |
| `cancel_publication(p_publication_id)` | Decision 2. |
| `mark_publication_published(p_publication_id, p_remote_url text default null)` | Decision 3. |
| `set_production_deadline(p_content_id, p_due_at timestamptz)` | Decision 4. A null date clears it. |
| `calendar_events(p_from timestamptz, p_to timestamptz, p_client_id uuid default null)` | Rows `(event_type, client_id, entity_id, content_id, title, starts_at, status, date_field)` in `[p_from, p_to)`, ordered by date, for every client the caller can see (or only `p_client_id`). A range that is empty or longer than 100 days is 22023 `invalid calendar range`; a client the caller cannot see is P0002. |

**22023 messages:** `only a client-approved revision can be scheduled`, `publication date must be in the future`, `invalid channel`, `this publication can no longer be changed`, `invalid remote url`, `invalid calendar range`, and the Increment 5 `this content can no longer be edited`.

**Statuses (`publication_status`):** `draft`, `scheduled`, `publishing`, `published`, `failed`, `retrying`, `canceled` (docs/04). v0.1 functions use `scheduled`, `published` and `canceled`; the others are reserved for automated publishing.

**Columns read by the tests:**
- `publications`: `id, client_id, content_id, revision_id, channel, scheduled_at, published_at, remote_url, status`.
- `contents`: `status, production_due_at, client_approved_revision_id`.

## Fixture

- **Workspaces and clients:** Workspace A {A1, A2} and Workspace B {B1}, with the same ids as earlier increments.
- **Internal users:**
  - `a_admin`;
  - `a_planner`: strategist with an explicit `publication.schedule` grant and no `publication.publish`;
  - `a_account` and `a_creative`: no publication capabilities. The creative has `content.edit`.
  - `b_admin`.
- **Client-side users:** `a1_approver`, `a1_viewer`, `a2_viewer`, `a2_approver`, `b1_approver`.
- **Content:**
  - Client-approved content A1, Extra (A1), A2 and B1.
  - Pend (A1): internally approved and waiting for the client, with a due date in 3 days.
- **Schedule:**
  - A1 is scheduled in 2 days by the planner, and the creative sets its production deadline to tomorrow.
  - A2 and B1 are scheduled in 2 days.
  - A1 has a meeting tomorrow.

## Mutation proof

Run against a throwaway prototype.
- **Satisfiable:** 50 of 50 assertions pass on the prototype.
- **Caught, 9 of 10:** scheduling without the client's approval; moving the production deadline with the publication; clients seeing internal events; no future-date check; recording a publication with `publication.schedule`; canceling never restoring the content; canceled publications on the calendar; clients seeing other clients' publications; no range limit.
- **Equivalent, 1 of 10:** "pin the latest revision instead of the client-approved one" is unobservable. In every state where scheduling is allowed, the latest revision is the approved one, and the client approved it.

## Deferred coverage

| Topic | Arrives with |
|---|---|
| Automated publishing (`publishing`, `failed`, `retrying`), remote ids and metrics sync | Later (docs/13 "not in v0.1") |
| Initiative milestones, recordings and seasonal events on the calendar | When those entities carry dates worth projecting |
| Publication profiles (`profile_id`) | When channel profiles exist |
| Drag and drop in the UI | Builder choice; the database semantics are frozen here |
