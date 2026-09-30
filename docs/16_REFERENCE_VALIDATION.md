# 16 — Technical Reference Validation

Validated against official/current documentation at specification time (2026-09-30).

## Supabase

- Row Level Security: https://supabase.com/docs/guides/database/postgres/row-level-security
- Queues/pgmq: https://supabase.com/docs/guides/queues

RLS provides database-level granular authorization. Supabase Queues provides durable Postgres-native message queues and is suitable for persistent background job delivery.

## Google Drive

- Change notifications: https://developers.google.com/workspace/drive/api/guides/push
- Change feed: https://developers.google.com/workspace/drive/api/guides/manage-changes
- Workspace Events / Drive events: https://developers.google.com/workspace/events/guides/events-drive

Drive supports push/watch/change mechanisms; v0.1 may intentionally start with simpler periodic sync before advancing to event subscriptions.

## Local AI models

- OpenAI gpt-oss: https://openai.com/index/introducing-gpt-oss/
- Ollama gpt-oss: https://ollama.com/library/gpt-oss
- Qwen3-VL 8B on Ollama: https://ollama.com/library/qwen3-vl:8b
- Qwen3 Embedding: https://ollama.com/library/qwen3-embedding

OpenAI states gpt-oss-20b can run with 16 GB memory. Ollama currently packages `gpt-oss:20b` at about 14 GB; Qwen3-VL 8B around 6.1 GB and Qwen3-Embedding 0.6B around 639 MB. These are initial candidates and should be benchmarked on the actual RTX 5060 Ti.

## Testing

- Playwright CI: https://playwright.dev/docs/ci
- Playwright screenshots: https://playwright.dev/docs/screenshots

## Observability (LATER maturity)

- OpenTelemetry: https://opentelemetry.io/docs/

## Agentic coding tools

- OpenAI Codex product: https://openai.com/codex/
- Claude Code CLI: https://code.claude.com/docs/en/cli-reference

The build protocol deliberately remains tool-agnostic. Current agent tools support unattended/non-interactive/background workflows, but repository tests/specs remain the authority.
