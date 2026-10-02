# AI Worker (`jmos_worker`)

Local Python worker that consumes the durable job queue in Postgres (docs/08 §2 and §5).
Increment 0 ships the **foundation only**. The one real job type is `system.healthcheck` v1, a
diagnostic round-trip with no side effects. No model adapters or AI pipelines exist yet
(Increment 3+).

## Security model

- **Outbound only.** The worker opens a Postgres connection and never listens on a port. Never
  expose it, or the Ollama runtime it will drive, to the internet.
- **Least privilege.** It connects as the `jmos_worker` role, which has no table privileges
  and may only execute `worker.claim_job`, `extend_lease`, `complete_job`, `fail_job` and
  `heartbeat`. At startup it requires a role that can execute the worker API, and it refuses a
  superuser, a BYPASSRLS role, or any role that can read `public.jobs` directly (exit code 3).
  This check cannot be disabled.
- **Untrusted payloads.** Job input is validated against the generated contract before the
  handler runs, and output is validated before it is stored. Validation errors report the
  schema rule and location, never payload values. Unexpected exceptions are stored as
  `unhandled_exception` with the exception type only; tracebacks stay in local logs.

## Delivery semantics (read before writing a handler)

At-least-once. A job can run again after a crash or an expired lease. Every write is fenced
by `(worker_id, attempt)`: if the lease was reclaimed, the stale worker gets `lease_lost`
and nothing changes. Completing a completed job returns `duplicate`. Handlers must therefore
be idempotent, and domain side effects must be committed atomically with completion through
a dedicated `worker.*` SQL function.

Retries: a retryable failure backs off `30s · 2^(attempt-1)` (capped at 1 h) up to
`max_attempts`, then becomes `dead_letter`. A permanent failure becomes `failed`. Both keep
`last_error` for a manual retry (job center, Increment 3).

## Running

```bash
pnpm setup:py                                   # once
export JMOS_WORKER_DATABASE_URL=postgresql://jmos_worker:jmos-worker-local-dev-only@127.0.0.1:54322/postgres
pnpm --filter @jmos/ai-worker check             # config, connectivity, role, contracts
pnpm worker                                     # run; Ctrl+C = graceful stop, twice = force
```

The local password comes from `supabase/seed.sql` and works only against the local Supabase
stack. In staging and production, an operator sets the role's password through secret management.

| Variable | Default | Meaning |
|---|---|---|
| `JMOS_WORKER_DATABASE_URL` | (required) | Postgres URL for the `jmos_worker` role |
| `JMOS_WORKER_ID` | `<hostname>-<pid>` | Lease owner / heartbeat id |
| `JMOS_WORKER_POLL_SECONDS` | `2` | Idle poll interval |
| `JMOS_WORKER_LEASE_SECONDS` | `300` | Lease length per attempt |
| `JMOS_WORKER_HEARTBEAT_SECONDS` | `15` | Liveness update interval, at most 30 s and shorter than the lease (the job center shows a worker as offline after 60 s of silence; a busy worker keeps beating while a job runs) |
| `JMOS_WORKER_LOG_LEVEL` | `INFO` | JSON-lines log level |
| `JMOS_OLLAMA_URL` | `http://127.0.0.1:11434` | Local model runtime. **Loopback addresses only**: never expose Ollama to the network |
| `JMOS_MODEL_REASONING` | `gpt-oss:20b` | Model behind the `reasoning` task profile (docs/08 §3) |
| `JMOS_MODEL_TIMEOUT_SECONDS` | `120` | Per-request model timeout (must be shorter than the lease) |

## Models (Increment 3)

Domain code asks for a task **profile** (`reasoning` for now), never for a model name. `models.py`
holds the `ModelAdapter` protocol and `OllamaAdapter` (`/api/chat`, JSON output, temperature 0).

- **Prompt-injection rule (docs/08 §10).** `build_messages` keeps pipeline instructions in the
  system message. Evidence goes into a separate user message, serialized as JSON inside an
  `<untrusted_evidence>` block that is labelled as data. Model output is untrusted too: the
  runner validates it against the job contract before it is written.
- **Errors.**
  | Situation | Result |
  |---|---|
  | Runtime unreachable, or HTTP 5xx | `model_unavailable` (retryable, with backoff) |
  | Model not installed (HTTP 404) | `model_not_found` (permanent; pull the model, then retry the job) |
  | Model answers without JSON | `model_output_invalid` (permanent) |
- **`ai.model_check.v1`.** Requested from **Automações → Testes do sistema**. It sends a fixed
  prompt and records `model_profile`, `model`, `latency_ms` and `ok`.
- **Setup.** Install Ollama on the worker machine, then run `ollama pull gpt-oss:20b`. Keep
  Ollama bound to `127.0.0.1`, which is its default.

Exit codes: `2` configuration error, `3` role too privileged, `4` database unreachable at startup.
Once running, database outages are logged and retried with backoff. The process does not exit.

## Tests

`pnpm --filter @jmos/ai-worker test` runs the unit tests. `pnpm test:integration` runs the tests
against a real Postgres wire connection (PGlite or Supabase; see `DEVELOPMENT.md`).
