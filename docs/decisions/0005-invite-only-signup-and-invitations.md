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

   It activates the membership and is single use. Every refusal is identical.
4. **E-mail confirmation is mandatory in production.** The hook only knows the e-mail, not the token. Without confirmation, someone who learned an invited address could sign up with it first and then accept. Confirmation proves control of the mailbox, which closes that path. Local development and CI auto-confirm, which is safe there.
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
