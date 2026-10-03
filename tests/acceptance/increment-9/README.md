# Increment 9: administration and invitations (protected acceptance contract)

**Authority:** `TEST_SPEC`. Builders must not edit these files (docs/11 "Protected paths").

**Spec anchors:**
- docs/13 demo loop, steps 1 and 2 (authenticate; create a Client with tenant isolation), which until now existed only in the seed;
- docs/03 journey "memberships/invite";
- docs/01 roles and capabilities;
- docs/05 §1 (isolation), §2 (authorization), §5 (secrets) and §6 (audit);
- docs/11 invariants 1 and 9;
- ExecPlan 0009 and ADR 0005.

## Decisions frozen here

They were taken autonomously under Nicolas's instruction of 2026-10-03 ("1": make v0.1 usable for real) and are recorded in ExecPlan 0009 and ADR 0005.

1. **People join through invitations.**
   - Workspace managers (`workspace.manage`) invite internal members with a role and capabilities.
   - Client managers (`client.manage`) invite portal members with a client role and client-safe capabilities only.
   - Client-side members do not manage access in v0.1.
2. **Invitations are one-time links.**
   - A token of 256 random bits is returned once. Only its SHA-256 hash is stored, and the API never exposes that hash.
   - An invitation expires after 7 days.
   - Inviting the same person to the same target again replaces (revokes) the pending invitation.
   - Active members are not invited again.
   - Internal and client-side identities stay separate within a workspace (the Increment 1 rule).
3. **Signup is invite-only, enforced by the database.** Supabase Auth calls `public.hook_before_user_created` before creating any account. The hook allows only an e-mail with a pending, unexpired invitation (compared lowercased and trimmed), and returns HTTP 403 otherwise. Only `supabase_auth_admin` may execute it. No service-role key exists in the app.
4. **Acceptance.**
   - It runs for the signed-in user. The caller's e-mail must match the invitation and must be **confirmed**.
   - The invitation must be pending and unexpired.
   - Accepting activates the membership with the invited role and capabilities and records who accepted.
   - Every refusal is the same 22023 `this invitation is not valid`, so a token reveals nothing.
   - The token is single use.
5. **Visibility.** Managers of the target see invitations (`workspace.manage` for internal ones, `client.manage` for client ones). Nobody writes the table directly, and anon reads nothing. Managers can list their members with e-mail, role, capabilities and status.
6. **Audit.** The actions `invitation.created`, `invitation.revoked` and `invitation.accepted` are recorded.

## Database API frozen by these tests

Everything lives in `public`. Errors follow the contract: P0002 when the target is not visible, then 42501, then 22023.

| Function | Rule |
|---|---|
| `invite_workspace_member(p_workspace_id, p_email text, p_role workspace_role, p_capabilities capability[] default '{}') → table(invitation_id uuid, token text)` | `workspace.manage` (decisions 1–2). |
| `invite_client_member(p_client_id, p_email text, p_role client_role, p_capabilities capability[] default '{}') → table(invitation_id uuid, token text)` | `client.manage` (decisions 1–2). |
| `revoke_invitation(p_invitation_id)` | The manager of the target. Only pending invitations. |
| `accept_invitation(p_token text) → table(workspace_id uuid, client_id uuid)` | Decision 4. `authenticated` only. |
| `workspace_members(p_workspace_id) → table(user_id, display_name, email, role, capabilities, status)` | `workspace.manage`. |
| `client_members(p_client_id) → table(user_id, display_name, email, role, capabilities, status)` | `client.manage`. |
| `hook_before_user_created(event jsonb) → jsonb` | Executable by `supabase_auth_admin` only (decision 3). |

**22023 messages:**
- `invalid email`;
- `this person is already a member`;
- `client memberships can only hold client-safe capabilities`;
- `a client-side member cannot become an internal member of the same workspace`;
- `this invitation is no longer pending`;
- `this invitation is not valid`.

**Columns read by the tests:**
- `invitations`: `id, workspace_id, client_id, email, workspace_role, capabilities, status, expires_at, invited_by, accepted_by`. The `token_hash` column exists but cannot be selected through the API.
- `auth.users.email_confirmed_at`, as Supabase stores it. The PGlite emulation adds it, together with the `supabase_auth_admin` role.

## Fixture

- **Workspaces and clients:** Workspace A {A1, A2} and Workspace B {B1}, with the same ids as earlier increments.
- **Members:**
  - `a_admin`;
  - `a_strategist`: no manager capabilities;
  - `a_mgr`: strategist with an explicit `client.manage`;
  - `b_admin`;
  - `a1_cadmin`: a client admin of A1.
- **People without memberships:** `nova@agencia.test`, `aprovador@cliente.test`, `outra@agencia.test` (confirmed) and `naoconfirmado@agencia.test` (unconfirmed).

## Mutation proof

Run against a throwaway prototype.
- **Satisfiable:** 53 of 53 assertions pass on the prototype.
- **Caught, 11 of 11:**
  - the hook allowing any signup;
  - accepting with an unconfirmed e-mail;
  - accepting with another e-mail;
  - a reusable token;
  - expiry ignored at acceptance;
  - a plaintext token stored;
  - clients seeing invitations;
  - no manager check for internal invitations;
  - client invitations with internal capabilities;
  - a readable token hash;
  - the hook callable by users.

## Deferred coverage

| Topic | Arrives with |
|---|---|
| Client admins inviting their own approvers and viewers | A later portal iteration (needs a client-side management capability) |
| E-mail delivery of invitations (SMTP templates) | Production setup: the link is shown to the inviter and sent by hand |
| Bulk invitations, invitation resend | When needed |
