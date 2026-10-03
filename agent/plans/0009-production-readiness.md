# ExecPlan 0009 — Production readiness for v0.1

**Status:** approved by Nicolas on 2026-10-03 ("1": make v0.1 usable for real before v0.2). This plan runs autonomously; its decisions are recorded here and, where they touch authentication, in ADR 0005.

**Spec anchors:**
- docs/13 demo loop, step 1 (authenticate) and step 2 (create a Client), which today are seed-only;
- docs/03 journey "memberships/invite";
- docs/05 §1, §5 and §6;
- docs/06 "Settings";
- docs/15 CORE baseline (environment separation, backups, migration gate, secrets outside source).

## Why

v0.1 passes every test, but an agency cannot start using it:
1. **No administration.** There is no screen to create clients or to bring people in. Users, memberships and clients come only from `supabase/seed.sql`, which never runs in production.
2. **No deployment path.** Nothing describes production: Supabase project, hosting, worker host, first admin, worker role password, backups.
3. **Debt flagged since Increment 1:**
   - there is no Content-Security-Policy;
   - accessibility is not linted;
   - the Drive adapter has never run against a real Google account.

## Parts

### P1 — Browser hardening (builder PR)
- **CSP:** a nonce-based Content-Security-Policy, set per request in `proxy.ts` (`script-src 'self' 'nonce-…' 'strict-dynamic'`, `frame-ancestors 'none'`, `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`; Supabase origin in `connect-src`). Development keeps `'unsafe-eval'`, which Next needs there.
- **HSTS:** set in production.
- **Accessibility lint:** `eslint-plugin-jsx-a11y` (recommended rules) for the web app and UI package. Fix what it finds.
- **Tests:**
  - E2E: pages carry the CSP with a nonce, and no CSP violation is logged on the login page.
  - Unit: the CSP builder.

### P2 — Increment 9: administration and invitations (TEST_SPEC + ADR 0005 + Builder)

**Gate.** This changes how accounts come into existence, which is an authentication architecture change. It follows the conservative option and is recorded in ADR 0005, under `authority:TEST_SPEC` plus `authority:ARCHITECTURE_CHANGE`.

**Decision (ADR 0005).**
- **Invite-only stays enforced by the database, and no service-role key enters the web app.**
  - Supabase Auth's e-mail signup is turned on.
  - A `before_user_created` Auth hook (a Postgres function) **rejects every signup without a pending invitation for that e-mail**.
- **Invitations:**
  - Workspace managers invite internal members (`workspace.manage`).
  - Client managers (`client.manage`; also the client admin, for client-side roles only) invite portal members.
  - An invitation is stored with a hashed token and an expiry. The app shows a one-time link that the inviter sends.
- **Acceptance happens in the database, for the signed-in user:**
  - It requires a **confirmed e-mail** that matches the invitation, and an unexpired token.
  - It activates the membership with the invited role and capabilities.
  - Production must enable e-mail confirmation (SMTP). The runbook checks it, because without it someone who knows an invited address could claim it.
- **Administration UI** in Settings, using the existing Increment 1 API:
  - create, rename and archive clients;
  - list members with role, capabilities and status;
  - change roles, revoke, invite, and revoke pending invitations;
  - portal access per client (invite, list, revoke) for internal client managers.

**TEST_SPEC covers:**
- invitation creation, with capability, tenant and argument errors;
- the hook (rejects unknown e-mails, accepts invited ones, rejects revoked or expired invitations);
- acceptance (needs a confirmed matching e-mail and a valid token; is single use; never reaches another tenant; client roles stay client-safe);
- revoking an invitation;
- RLS (who sees invitations; the token hash is never readable);
- audit entries.

### P3 — Deployment runbook and operator tooling (builder PR)
- **`DEPLOYMENT.md`:**
  - environments;
  - Supabase project setup: `supabase db push`, no seed, Auth settings (confirmations, SMTP, site URL and redirects, the hook);
  - web hosting environment variables;
  - worker host: systemd unit and a Windows service, Ollama, Drive keys;
  - backups/PITR per plan;
  - the migration gate and rollback;
  - first admin.
- **`scripts/ops`**, run by an operator with the owner database URL, never by the app:
  - `ops:bootstrap`: creates the first workspace and an admin invitation for the owner's e-mail, and prints the link;
  - `ops:worker-password`: sets the `jmos_worker` login password from an environment variable;
  - `ops:check`: checks a target environment (migrations applied, no seed identities, worker role least-privileged, Auth hook installed).

### P4 — Real Drive check (builder PR)
- `python -m jmos_worker drive-check --workspace <id> --ref <ref> --folder <id>` lists the folder with the real adapter and prints only counts. It writes nothing to the database. It lets the agency validate a service account and folder sharing before connecting a client.
- `apps/ai-worker/README.md` gets a step-by-step guide for creating the Google service account.

## Out of scope (needs Nicolas)
Creating cloud resources (Supabase project, hosting, domain, SMTP, Google service account) costs money and uses his accounts. Everything is prepared so he can do it, or authorize me to do it, step by step.

## Deferred, with reasons
| Item | Why |
|---|---|
| Generated DB types | `supabase gen types` needs Docker locally, and the CI change needs `ARCHITECTURE_CHANGE`. Zod already validates every boundary at runtime. |
| Client admins inviting their own people in the portal | Needs a client-side management capability (docs/01 says client admins manage client-side members); v0.1 keeps access management internal |
| Authenticated E2E locally | Needs the Supabase Auth server (Docker). CI runs them on every PR. |

## Architecture gate
- **P2:** yes. Authentication (signup via an invitation hook) is handled through ADR 0005 and a TEST_SPEC.
- **P1, P3, P4:** no. They harden or document without changing domain, roles or trust boundaries.
