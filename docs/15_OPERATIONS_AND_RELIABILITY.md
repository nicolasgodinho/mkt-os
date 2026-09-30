# 15 — Operations and Reliability

## CORE baseline

- persistent status for integrations/jobs;
- structured error logs;
- audit trail for critical actions;
- retry/idempotency;
- development/staging/production separation;
- database backups enabled according to hosting plan;
- migration review/gate for destructive changes;
- secrets outside source code.

## LATER maturity

- full OpenTelemetry traces/metrics/logs;
- automated restore drills/PITR workflows;
- circuit breakers and quota dashboards;
- feature flag platform/staged rollout;
- automated rollback based on health;
- incident console/runbooks;
- advanced PII/data classification and retention tooling.

## Integration health

Every connection exposes:
- status;
- last successful sync;
- last error;
- scopes/identity summary;
- reconnect action;
- cursor/subscription status where applicable.

## AI worker health

Expose:
- online/offline heartbeat;
- active model profile;
- running/queued/failed job counts;
- last successful job;
- dead-letter jobs;
- ability to cancel/retry safe jobs.

## Data lifecycle

Client offboarding eventually follows:
`active → closing → export → revoke integrations → archive → retention window → delete/anonymize according to policy/contract`.

MVP needs at least archive/export-aware data ownership; full deletion automation is LATER.
