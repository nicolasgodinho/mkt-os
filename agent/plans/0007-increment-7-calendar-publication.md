# ExecPlan 0007 — Increment 7: Calendar and publication

**Status:** approved under Nicolas's standing instruction (2026-10-02). This plan runs autonomously. Its decisions are recorded here and in the TEST_SPEC README.

**Spec anchor:** docs/13 Increment 7: typed calendar projection, publication schedule, internal and portal calendar views.

**Contract:** `tests/acceptance/increment-7/` (PR nicolasgodinho/mkt-os#25). Where the tests and this plan disagree, the tests win.

## Goal

Close the v0.1 demo loop (docs/13, steps 16–17):

> client-approved revision → publication scheduled on a date → visible on the internal and portal calendars → recorded as published.

The calendar is a projection of dated records, never a second copy of them (docs/06).

## Decisions

The README freezes these decisions:
1. Only content whose latest approved revision was approved by the client can be scheduled (`publication.schedule`). The publication pins that revision, and the date must be in the future.
2. Rescheduling and canceling work on scheduled publications only. Canceling the last one returns the content to `approved`.
3. A person records the publication (`publication.publish`): status, time and an optional `http(s)` link. The revision and the client approval are never touched.
4. The production deadline (`contents.production_due_at`, `content.edit`) and the publication date are independent (docs/11 invariant 7).
5. `calendar_events` projects publication, production deadline, approval deadline and meeting. Each event names the one date field a move changes.
6. Clients see their publications and approval deadlines. Production deadlines, meetings and canceled publications stay internal.
7. Scheduled content is frozen: cancel its publications to edit it.

Builder-level decisions (not frozen by tests):
- **No drag and drop in v0.1.** Dates change through explicit forms on the record ("Mudar data da publicação", "Prazo de produção"). This keeps the typed semantics obvious and accessible; drag and drop can call the same actions later.
- **Views.** Month and list. Week view is deferred, because month plus list cover the demo.
- **Times.** Times are entered and shown in America/Sao_Paulo (`-03:00`, as in Increment 2) until workspaces carry a timezone.
- **Backlog.** The unscheduled backlog is the client-approved content with no publication. It lives below the calendar and has its own schedule form.

## In scope

- **Migration `20261002200000_calendar_publication.sql`:**
  - `publication_status`, `publications` (composite foreign keys to the content and its revision), `contents.production_due_at`;
  - the frozen functions;
  - publication RLS for internal staff and client members.
- **Builder pgTAP `090_calendar_publication`:** audit action names, function hardening, table constraints, no deadline on closed content.
- **Web, internal:**
  - `/w/[ws]/calendar` (Calendário): month and list views, client and type filters, the unscheduled backlog.
  - Content Studio "Publicação" panel: production deadline, schedule, move, cancel, record as published.
- **Web, portal:**
  - "Próximos 7 dias" on the portal home.
  - `/portal/[client]/calendar` for the next 30 days.
  - The "Conteúdo e calendário" area links there.
- **Seed.** A client-approved post for Cliente Demo A, scheduled in 3 days, with a production deadline.
- **Tests:**
  - Vitest: business-time conversions, month grid and range, grouping; the error map, with a drift check.
  - E2E desktop: schedule from the backlog, move, record as published; the month view; the API boundary.
  - E2E phone: next 7 days and the calendar for the approver; another client sees nothing.

## Non-goals (deferred)

| Item | Destination |
|---|---|
| Automated social publishing, remote ids, metrics sync | Later (docs/13 "not in v0.1") |
| Week view, drag and drop, inspector peek | Later UI iteration |
| Initiative milestones, recordings, seasonal events on the calendar | When those entities carry dates |
| Workspace timezone | When workspaces carry settings |

## Security

- **Writes:** everything goes through SECURITY DEFINER functions with `search_path = ''`, executable by `authenticated` only. Tables have RLS and no write grants.
- **Calendar reads:** `calendar_events` returns only clients the caller can see. For client members it returns only the client-visible event types and statuses.
- **Remote links:** they are restricted to `http(s)` in the database and rendered with `rel="noopener noreferrer nofollow"`.

## Architecture gate

**No.** Publication and its capabilities (`publication.schedule`, `publication.publish`) already exist in docs/01, docs/02 and docs/10. Roles are unchanged, and there is no new trust boundary.
