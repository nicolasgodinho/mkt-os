# Increment 6: collaboration and portal (protected acceptance contract)

**Authority:** `TEST_SPEC`. Builders must not edit these files (docs/11 "Protected paths").

**Spec anchors:**
- docs/13 Increment 6: ApprovalRequest and Decision; comments and thread basics; Client Portal Home and My Approvals; revision-approval acceptance tests.
- docs/04 ApprovalRequest.
- docs/07 §9, §14 and §15.
- docs/10 `threads`, `comments`, `approval_requests`, `approval_decisions`.
- docs/01: client roles.
- docs/11 invariants 2 (approval versioning), 9 (portal boundary) and 10 (AI offline resilience: no worker is involved).

These tests build on the Increment 5 content API. Their fixture creates internally approved content through it.

## Decisions frozen here

They were taken autonomously under Nicolas's standing instruction of 2026-10-02 and are recorded in ExecPlan 0006.

1. **What can be sent to the client.** Only an **internally approved** revision: the content is `approved` and the revision is its `approved_revision_id`.
   - The request requires `approval.request`.
   - The content moves to `client_review`.
   - A content has at most one open request.
2. **Who decides.** Only client-side members whose client membership grants `approval.decide`: the client admin, the approver, or a collaborator with an explicit grant. Internal staff can never decide on the client's behalf, whatever their capabilities.
   - Approving sets `client_approved_revision_id` to the exact revision and returns the content to `approved`.
   - Requesting changes sends the content back to `producing`.
   - Each decision is stored as an immutable `approval_decisions` row.
3. **Stale requests.** Any change to the content while the client reviews (a payload edit, or going back to production) **cancels** the open request. A later revision is never client-approved without a new request (docs/11 invariant 2).
4. **What clients see.**
   - Approval requests of their own client.
   - Exactly the revisions that were sent to them.
   - Client-visible comments.

   Working content (`contents`), other revisions and internal comments stay internal.
5. **Comments.**
   - They are threaded per target and visibility (`internal` or `client`). The only target type for now is `content`.
   - Internal staff with access to the client may write both visibilities.
   - Client members may write client-visible comments, and only on content that was sent to them. Viewers are read-only.

## Database API frozen by these tests

All of it lives in `public` and is executable by `authenticated` only. Errors follow the same contract as before: P0002 when the target is not visible, then 42501, then 22023.

| Function | Rule |
|---|---|
| `request_client_approval(p_revision_id, p_due_at timestamptz default null) → uuid` | `approval.request`. The revision must be the content's internally approved revision, and there must be no open request. |
| `decide_approval(p_request_id, p_decision text, p_comment text default null)` | `approve` or `changes`. Client-side `approval.decide` only. The request must be open and not stale. |
| `cancel_approval_request(p_request_id)` | `approval.request`. The content returns to `approved`. |
| `add_comment(p_target_type text, p_target_id uuid, p_body text, p_visibility text default 'client') → uuid` | See decision 5. A blank body or an unknown target is 22023. |
| `portal_approvals(p_client_id)` | Rows `(request_id, status, content_title, channel, format, revision_number, payload, requested_at, due_at, decided_at)` for members and internal staff of that client. |

**Statuses (`approval_status`):** `requested`, `approved`, `changes_requested`, `canceled`, `expired`.

**Columns read by the tests:**
- `approval_requests`: `id, client_id, content_id, revision_id, status, requested_by`.
- `approval_decisions`: `approval_request_id, approver_user_id, decision, comment`.
- `threads`: `id, target_id, visibility`.
- `comments`: `id, thread_id, client_id, author_id, body`.
- `contents.client_approved_revision_id`.

## Fixture

- **Workspaces and clients:** Workspace A {A1, A2} and Workspace B {B1}, with the same ids as earlier increments.
- **Internal users:** `a_admin`, `a_account` (`approval.request`), `a_creative` (no `approval.request`), `b_admin`.
- **Client-side users of A1:** `a1_cadmin`, `a1_approver`, `a1_collab`, `a1_collab_appr` (collaborator with an `approval.decide` grant), `a1_viewer`.
- **Other client-side users:** `a2_viewer`, `b1_approver`.
- **Content:** internally approved content A1, Extra (A1), A2 and B1, created through the Increment 2 and 5 APIs, plus an open request on B1.

## Mutation proof

Run against a throwaway prototype.
- **Caught, 6 of 8:** internal staff deciding; stale requests not canceled; clients seeing every revision; clients seeing internal comments; requesting approval for a revision that is not approved; viewers commenting.
- **Equivalent, 2 of 8:**
  - "approval sets the latest revision" is unobservable, because the stale-request rule keeps the latest revision equal to the requested one while a request is open;
  - "decide twice" is also blocked by the content status check.

## Deferred coverage

| Topic | Arrives with |
|---|---|
| Approval assignments, multiple required approvers, due-date expiry job | Later (`expired` is reserved) |
| Batch approval | Later, when policy allows (docs/07 §9) |
| Notifications and Inbox | Later |
| Requests (client intake) | v0.2 |
| Calendar in the portal | Increment 7 |
