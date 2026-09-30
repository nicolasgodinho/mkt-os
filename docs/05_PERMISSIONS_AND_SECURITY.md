# 05 — Permissions and Security

## 1. Isolation — BLOCKER

Every exposed client-owned table must be protected by Postgres RLS. UI hiding is never a security boundary.

Tests must prove:
- internal authorized member can access assigned client;
- client member can access only own client;
- guessing UUIDs from another client returns no unauthorized data;
- unauthenticated/incorrect roles cannot perform privileged writes;
- service/worker paths use narrowly-scoped server credentials.

## 2. Authorization

Use role defaults + capability checks. High-risk operations require explicit capabilities:

- activate/supersede hard rules;
- approve client-visible content;
- publish/schedule;
- modify integrations;
- change memberships/permissions;
- destructive archive/delete;
- production admin actions.

## 3. AI trust boundary — BLOCKER

LLM output is untrusted input to application code.

Required pattern:

`AI proposes structured action → schema validation → authorization/policy validation → deterministic application service → persistence/event`

Never give a model unrestricted SQL, filesystem or cross-tenant access.

## 4. Prompt injection defense

- Retrieved documents/web pages are explicitly delimited as untrusted evidence.
- Tool instructions never come from retrieved content.
- Source trust level is carried with retrieved chunks.
- External text cannot modify system prompts, active rules, credentials or permissions.
- Tool calls with side effects require application policy checks independent of model text.

## 5. Secrets

Production secrets never enter repo, prompt history, logs or agent fixtures. Use environment/secret storage. Coding agents operate against dev/test credentials.

## 6. Audit

Write immutable/separate audit entries for:
- membership/permission changes;
- integration connect/disconnect;
- Rule activation/supersession;
- approval decisions;
- publication actions;
- destructive data actions;
- privileged admin impersonation/support actions;
- material automated actions.

Audit entry: actor, action, target, timestamp, client/workspace, before/after summary where safe, trace/request ID.

## 7. Soft deletion

Core entities use archive/soft-delete first. Permanent deletion is a separate privileged operation and must respect retention/legal requirements.
