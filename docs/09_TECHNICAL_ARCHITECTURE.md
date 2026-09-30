# 09 — Technical Architecture

## Recommended v0.1 stack

### Web
- Next.js + TypeScript
- Tailwind + shadcn/ui (or equivalent internal design primitives)

### Data/platform
- Supabase/Postgres
- Auth
- Row Level Security
- Realtime where useful
- `pgvector` for embeddings
- Supabase Queues/`pgmq` for durable background jobs

### Files
- Google Workspace Shared Drive via Drive API
- Postgres `FileRecord` registry for semantics/sync state

### Local AI
- Python worker
- Ollama/model runtime adapter initially
- faster-whisper adapter

### Testing
- Vitest/unit domain tests
- database/RLS tests (pgTAP/Supabase local testing)
- Playwright E2E + screenshots/traces

## Deployment shape

```text
Browser
  │
Next.js App/API
  │
Postgres/Supabase ─── Google APIs
  │     │
  │     └── Queue/Outbox
  │              │
  │          Local AI Worker
  │
Realtime/notifications
```

## Module boundaries

Suggested monorepo:

```text
apps/
  web/
  ai-worker/
packages/
  core/
  identity/
  clients/
  knowledge/
  strategy/
  operations/
  content/
  collaboration/
  integrations/
  ai-contracts/
  ui/
  test-fixtures/
supabase/
  migrations/
  tests/
docs/
agent/
```

Modules may depend on `core` contracts but should not reach into another module's private persistence directly. Cross-module side effects use application services/events.

## Domain events/outbox — CORE

Important state changes emit durable domain events through an outbox pattern when downstream work is required.

Examples:
- `content.approved`
- `rule.activated`
- `meeting.completed`
- `publication.published`
- `request.accepted`

Consumers must be idempotent.

## Drive connector

MVP may poll the Drive changes feed on a short interval. Store sync cursor/state. Later move appropriate workloads to Drive push/Workspace Events subscriptions.

`FileRecord` tracks `drive_file_id`, relevant revision/change ID, mime type, client/project/content links, sync/index status and checksum/hash when useful.

## Scheduler vs Queue

- Scheduler decides **when** periodic/delayed work becomes due.
- Queue guarantees **execution** of background work.

Do not encode recurring scheduling solely as long-lived queue messages.

## Observability baseline

CORE baseline:
- structured logs with `trace_id`, `workspace_id`, `client_id`, `job_id` where available;
- job/integration status persisted;
- error reporting.

LATER maturity:
- OpenTelemetry traces/metrics/log correlation and full dashboards.

## Environments

`local → CI/preview → staging → production`

Autonomous agents may deploy preview/staging when configured. Destructive migrations, authorization model changes and sensitive production operations remain gated.
