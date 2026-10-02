# ExecPlan 0003 — Increment 3: AI queue/worker

**Status:** approved under Nicolas's standing instruction (2026-10-02: "termina, sem ficar parando"), so it runs autonomously. Decisions are recorded here and in the TEST_SPEC README for later review.

**Spec anchor:** `docs/13_MVP_BUILD_PLAN.md`, Increment 3: durable queue contract, local Python worker, model adapter, job center/status, idempotency tests.

**Contract:** `tests/acceptance/increment-3/` (TEST_SPEC PR nicolasgodinho/mkt-os#13). When this plan and the tests disagree, the tests win.

## Problem

Increment 0 delivered the durable queue (ADR 0001) and a worker that runs only a diagnostic job. Three things are missing:
- People cannot see or operate the queue: no status page, no cancel, no retry.
- The worker cannot talk to a model.
- docs/15 asks for "AI worker health", and docs/03 journey G (worker offline) is not visible anywhere.

## Goal

- A **job center**: worker health, per-status counts, recent jobs, and safe cancel and retry.
- A **model adapter** in the worker with task profiles (docs/08 §3–§4), proven end to end by an `ai.model_check.v1` job.
- No change to the queue's delivery guarantees (at-least-once delivery, fencing, idempotency).

## Decisions (frozen in the TEST_SPEC README)

1. **Capability.** Request, cancel and retry need `workspace.manage`. Reading follows the Increment 0 RLS rule. No new capability is added.
2. **System jobs only.** `request_system_job` enqueues only allow-listed types (`system.healthcheck` v1, `ai.model_check` v1). Domain jobs get their own capability-checked enqueue functions (Increment 4+).
3. **Cancel.** Only `queued` and `retry_wait` jobs can be canceled. A running job is never interrupted.
4. **Retry.** Allowed for `failed`, `dead_letter` and `canceled` jobs.
   - It never resets `attempts`, which are the fencing token.
   - It raises `max_attempts` to `max(current, min(attempts + 3, 20))`.
   - At 20 attempts the job is final (22023).
5. **Model check.** The model check uses profile `reasoning` and a fixed prompt. The job input is empty.

## In scope

**Migration `20261002120000_job_center.sql`.** Adds `request_system_job`, `cancel_job`, `retry_job` and `job_center_summary`, plus the helpers `app.can_see_job` and `app.require_manageable_job`. Every change is audited.

**`packages/core`.** Adds the `ai.model_check` v1 contract (zod). Its JSON Schema is generated for the worker.

**Worker (`apps/ai-worker`):**
- **`models.py`.** A `ModelAdapter` protocol and `OllamaAdapter` (stdlib HTTP, `/api/chat`, `format: json`, `stream: false`).
- **Profiles.** Map profile names to model names: `reasoning` defaults to `gpt-oss:20b`, overridable with `JMOS_MODEL_REASONING`.
- **Messages.** `build_messages` keeps the policy/system text separate from untrusted evidence. Evidence is serialized as a JSON block in a user message labelled untrusted (docs/08 §10, docs/05 §4).
- **Configuration.** `JMOS_OLLAMA_URL` defaults to `http://127.0.0.1:11434` and **must be a loopback address**. The worker never reaches a model runtime over the network, and Ollama must not be exposed to the internet.
- **`ai.model_check.v1` handler.**
  - It sends a fixed prompt and requires JSON `{"ok": true}`.
  - It reports `model_profile`, `model`, `latency_ms` and `ok`.
  - Errors are mapped as follows: runtime unreachable → retryable `model_unavailable`; a malformed answer → non-retryable `model_output_invalid`.
- **Heartbeat.** Reports the active model profile.

**Web: Automações → Central de jobs** (`/w/[workspace]/automations`). The global nav item "Automações" becomes available.
- Worker health:
  - online/offline: a heartbeat within 60 s;
  - active model profile;
  - version and job types.
- Summary counts, recent jobs (status filter), and the last error code and message.
- Request healthcheck / model check, cancel and retry. These are visible only with `workspace.manage` and enforced by the database.

**Tests:**
- Builder pgTAP `050_job_center`.
- pytest for the adapter: a fake HTTP server, loopback-only config, message separation, error mapping.
- Vitest for the formatters.
- E2E: an admin requests a healthcheck and sees it queued; a strategist sees no actions; a client user gets 404.

**Docs:** DEVELOPMENT.md (job center, Ollama setup) and the worker README.

## Non-goals (deferred)

| Item | Destination |
|---|---|
| Domain job side effects written in the completion transaction | Increment 4 (`meeting.extract`) |
| Realtime/push status | When needed (the page reads on request; a refresh link is shown) |
| VRAM model manager (unload/load between profiles) | When a second profile is in use (Increment 4: transcription, vision) |
| Embeddings and retrieval | Increment 4+ |
| Job retention/archival; per-tenant fairness | ADR 0001 revisit criteria |
| Canceling running jobs | Needs worker cooperation; not in v0.1 |

## Security

- **No new trust boundary.** The worker already runs on the agency machine, and the model runtime is local, loopback only.
- **Untrusted input.** Model output is untrusted: it is validated against the contract schema before being written (existing runner).
- **Error payloads.** They carry codes and short messages, never payload values.

## Observability / audit

- **Audit actions:** `job.requested`, `job.canceled`, `job.retried`.
- **Worker logs:** they carry `job_id`, `trace_id`, `model_profile` and latency.

## Rollout / rollback

The change is additive. Rollback is a new migration dropping the four functions and the two helpers.

## Architecture gate required?

`no`. There is no entity, role or capability change and no new trust boundary. Retry and cancel fill the slots ADR 0001 reserved for the job center.
