# ExecPlan 0006 — Increment 6: Collaboration and portal

**Status:** approved under Nicolas's standing instruction (2026-10-02). This plan runs autonomously. Its decisions are recorded here and in the TEST_SPEC README.

**Spec anchor:** docs/13 Increment 6: ApprovalRequest and Decision, comments and thread basics, Client Portal Home and My Approvals, revision-approval acceptance tests.

**Contract:** `tests/acceptance/increment-6/` (PR nicolasgodinho/mkt-os#22). Where the tests and this plan disagree, the tests win.

## Goal

Close the client side of the v0.1 demo loop (docs/13, steps 13–15):

> internally approved revision → sent to the client → the client approves or asks for changes on that exact revision, in the portal, from a phone.

Comments give both sides a place to talk about a content without mixing internal notes with what the client sees.

## Decisions

The README freezes these decisions:
1. Only the internally approved revision can be sent (`approval.request`). A content has at most one open request, and it moves to `client_review`.
2. Only client-side members with `approval.decide` decide. Internal grants never count. Each decision is an immutable row.
3. Any change while the client reviews cancels the open request (docs/11 invariant 2).
4. Clients see their requests, exactly the revisions sent to them, and client-visible comments. Working content and internal comments stay internal.
5. Comments are threaded per target and visibility. Client members comment only on content sent to them. Viewers are read-only.

Builder-level decisions (not frozen by tests):
- **Who may comment on the client side.** The client-side capabilities `approval.decide` or `request.submit`. This maps "viewers are read-only" onto the existing capability table without a new capability.
- **Editing during client review.** `save_content_payload` accepts `client_review`; the stale-request trigger then cancels the open request. The team never needs to cancel by hand before fixing a typo.
- **Comment author name.** It is copied onto the comment at write time, so clients can see who wrote without reading the internal `users` table.

## In scope

- **Migration `20261002180000_collaboration_portal.sql`:**
  - `approval_status`, `approval_requests` (one open per content), `approval_decisions` (immutable trigger), `threads`, `comments`, `contents.client_approved_revision_id`;
  - the stale-request trigger;
  - the frozen functions;
  - RLS for internal staff and client members.
- **Builder pgTAP `080_collaboration_portal`:** audit action names, helper privileges, the immutable decision trigger, the comment length limit.
- **Web, internal:**
  - Content Studio: "Aprovação do cliente" (send, cancel, history with the client's decision) and two comment threads (internal and client).
  - `/w/[ws]/approvals` (Aprovações): every request of the workspace's visible clients, by status.
- **Web, portal (mobile first):**
  - Portal home: "Precisa de você" lists open requests, most urgent first.
  - `/portal/[client]/approvals`: all requests.
  - `/portal/[client]/approvals/[request]`: large preview of the exact revision, the decision with an optional comment, the client thread, and a notice for canceled requests.
- **Seed.** A story for Cliente Demo A waiting for the client's approval.
- **Tests:**
  - Vitest: `needsAttention` ordering; the error map, with a drift check against the migration.
  - E2E (phone):
    - the approver finds the request, comments, and asks for changes;
    - the approver approves; a second decision is refused;
    - an edit by the team cancels the request;
    - a collaborator comments but cannot decide.
    - Internal comments never appear in the portal.

## Non-goals (deferred)

| Item | Destination |
|---|---|
| Approval assignments, several required approvers, expiry job (`expired`) | Later |
| Client requests (Solicitações) | Later portal increment |
| Notifications (email, WhatsApp) | Later |
| Comments on other targets (pautas, assets) | When those screens need them |
| Calendar in the portal | Increment 7 |

## Security

- **Writes:** everything goes through SECURITY DEFINER functions with `search_path = ''`, executable by `authenticated` only.
- **Decisions:** internal capabilities never reach `decide_approval`; it reads only client-side membership capabilities.
- **Client reads:** RLS gives clients only:
  - `approval_requests` and `approval_decisions` of their client;
  - the revisions referenced by a request;
  - comments in client threads.
- **Portal pages:** they check an active client-side membership for exactly that client and render the shared 404 otherwise. The database enforces every read anyway.

## Architecture gate

**No.** The entities come from docs/04 and docs/10, and the roles and capabilities are unchanged. The portal boundary already exists (Increment 1); this increment only adds data behind it. There is no new trust boundary.
