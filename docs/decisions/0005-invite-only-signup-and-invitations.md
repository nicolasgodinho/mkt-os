# ADR 0005: Invite-only signup enforced by the database, with one-time invitations

- **Status:** accepted. It was decided autonomously under Nicolas's instruction of 2026-10-03 (ExecPlan 0009: make v0.1 usable for real) and is recorded for later review.
- **Date:** 2026-10-03
- **Scope:** how accounts and memberships come into existence (authentication architecture). It does not change roles, capabilities or RLS.
- **Requires:** `authority:ARCHITECTURE_CHANGE`.

## Context

Increment 1 made access invite-only by turning Supabase Auth signups off. Users, memberships and clients came only from `supabase/seed.sql`, which never runs in production, so an agency could not onboard anyone.

The usual way to invite with Supabase is `auth.admin.inviteUserByEmail`, which needs the **service-role key**. DEVELOPMENT.md and docs/05 keep that key out of the web app: the app only ever acts with the user's session, and RLS decides.

## Decision

1. **Signups are on, and the database decides who may sign up.** Supabase Auth's `before_user_created` hook calls `public.hook_before_user_created(event)`. It returns `{}` only when the e-mail (lowercased and trimmed) has a pending, unexpired invitation; otherwise it returns `{"error": {"http_code": 403}}`. Only `supabase_auth_admin` can execute it. A direct call to `/auth/v1/signup` with the public key is therefore still refused for anyone not invited.
2. **Invitations are database rows,** created by managers through capability-checked functions:
   - `workspace.manage` invites internal members;
   - `client.manage` invites portal members, with client-safe capabilities only.

   A 256-bit token is returned once. Only its SHA-256 hash is stored, the hash column is not selectable through the API, and invitations expire after 7 days. The inviter sends the link `/convite/<token>`; v0.1 does not send e-mail itself.
3. **Acceptance is a database function for the signed-in user.** It requires:
   - the caller's Auth e-mail to equal the invitation's;
   - **`email_confirmed_at` to be set**;
   - a pending, unexpired invitation.

   Acceptance (`accept_invitation`) implements the following strict rules, in order, after the e-mail/token checks:
   - **Account freshness check:** Let `v_confirmed_at` be the caller's `auth.users.email_confirmed_at` and `v_inv` the invitation. A "fresh account" is one confirmed during this invitation's life (`v_confirmed_at >= v_inv.created_at`). A "pre-existing account" (`v_confirmed_at < v_inv.created_at`) is accepted as before, leaving its password and sessions untouched.
   - **Proven inbox for fresh accounts:** For a fresh account, the current session must have proven the inbox. The JWT claim `amr` must contain an entry with `method = 'otp'` and `timestamp` within the last 30 minutes, or it raises 42501.
   - **Password wiping for fresh accounts:** On success for a fresh account, in the same transaction, the caller's `auth.users.encrypted_password` is set to `''` (wiping any password set before the inbox was proven) and all `auth.sessions` rows for the caller except the current `session_id` are deleted.
   - The workspace row is locked (`for update`) before membership changes.
   - If the caller is already an **active** member of the target, it raises `22023 'this person is already a member'` (the invitation stays pending).
   - If the `invited_by` user (which is nullable, to allow an operator bootstrap owner) is no longer an active member holding the required `manage` capability, it raises `22023 'this invitation is not valid'`.

   The token is 64 lowercase hex characters (256 bits, asserted). It is returned once, only its SHA-256 hash is stored, and the hash column is not selectable through the API. Invitations expire after 7 days.
4. **E-mail confirmation is mandatory in production, and invited signup is passwordless.** The app creates invited accounts through an e-mail link (Supabase OTP/magic link), never with a password. A password may be set only later, by a session that proved the inbox. Without confirmation, someone who learned an invited address could sign up with a password first. Confirmation proves control of the mailbox.

   **Residual risk:** An attacker who signs up with a password and obtains a session *before* the real person confirms the inbox and accepts the invitation could theoretically hold a valid access token in the seconds between the real user's confirmation and their acceptance, because the token remains valid until JWT expiry. Mitigation: a short JWT expiry (≤ 600 s, see DEPLOYMENT.md), and the attacker's deleted session cannot be refreshed. (Note: A manager with `member.manage` may explicitly invite admins — this is intended).
5. **No service-role key anywhere in the app.** Operator tooling (ExecPlan 0009 P3) bootstraps the first workspace by creating an invitation with the database owner URL. It never holds Auth admin powers.

## Consequences

- Production setup must configure SMTP, keep e-mail confirmation on, and enable the hook. `DEPLOYMENT.md` and `ops:check` verify these settings.
- The Increment 1 check "self-signup is disabled" becomes "signup without an invitation is refused". The invariant (invite-only access) holds, enforced one layer deeper.
- A person invited to several workspaces uses one account and accepts each link while signed in.

## Alternatives considered

- **Service-role invites from the web app.** Rejected: it puts a credential that bypasses RLS on the request path.
- **An operator-only CLI that uses the service role.** Rejected as the main path: every new approver would depend on an operator. It is still possible for emergencies.
- **Signups on without a hook,** relying on memberships alone. Rejected: anyone could create accounts, and the "no access" surface would grow.

## Migration / rollback

The migration is additive (`invitations`, its functions, the hook). Rollback disables the hook in the Auth configuration, turns signups off again, and drops the new objects.
