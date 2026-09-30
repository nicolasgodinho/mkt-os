# 08 — AI Architecture

## 1. AI is a service layer, not the data model

Business truth remains in typed domain records. Vector retrieval and LLM outputs augment those records but never replace them.

## 2. Local worker topology

```text
Cloud Web/API + Postgres/Supabase
            │
        durable queue
            │ outbound polling/worker connection
            ▼
Local AI Worker (RTX 5060 Ti 16 GB)
  ├─ text/reasoning model adapter
  ├─ vision model adapter
  ├─ embedding model adapter
  ├─ transcription adapter
  └─ optional image/video generation later
```

Portal and non-AI workflows function if worker is offline.

## 3. Model strategy

Do not hard-wire domain logic to a specific model. Use adapters and task profiles.

Initial local candidates validated as available at specification time:
- reasoning/tool use: `gpt-oss:20b` (fits 16 GB class hardware according to OpenAI; Ollama package ~14 GB);
- vision: `qwen3-vl:8b` (~6.1 GB Ollama package);
- embeddings: `qwen3-embedding:0.6b` (~639 MB Ollama package);
- transcription: faster-whisper/Whisper family, benchmark locally.

These are implementation defaults, not architectural invariants. Benchmark quality/latency on actual hardware before freezing production profiles.

## 4. Model manager

Because VRAM is limited, jobs declare `model_profile` and the worker may unload/load models between task classes. Queue priority prevents low-value batch work from blocking client-facing work.

## 5. Job contract — BLOCKER

Each job includes:

- `id`, `type`, `schema_version`;
- `workspace_id`, `client_id?`;
- `idempotency_key`;
- input references, not raw secrets;
- `priority`;
- `attempts`, `max_attempts`;
- `lease_owner`, `lease_until`;
- timestamps;
- `model_profile`, `pipeline_version`;
- status/error.

Output writes must be idempotent/transactional. Failed permanent jobs go to dead-letter/failed state for manual retry.

## 6. Knowledge retrieval

Hybrid retrieval:
- exact/lexical search + filters for IDs/rules/names;
- semantic vector retrieval for conceptual questions;
- optional reranking later/when beneficial.

Retrieval always carries source IDs, trust levels and validity metadata.

## 7. AI output types

Prefer strict structured outputs validated by schema.

Examples:
- `meeting.extract.v1` → proposed Facts/Rules/Decisions/Insights/Tasks;
- `opportunity.generate.v1` → evidence-backed opportunity candidates;
- `content.generate.v1` → draft payload + claims/sources;
- `rules.semantic_check.v1` → violations/suggestions, not direct database mutation.

## 8. Human → AI → Human pattern

For high-judgment work:
1. Human sets intent/constraints.
2. AI expands/researches/drafts/critiques.
3. Human chooses/edits/approves.

For deterministic low-risk workflows, approval may be policy-configured away later.

## 9. AI versioning

Every material output records:
- model/profile/version;
- prompt template + version;
- pipeline version;
- relevant rule snapshot/version;
- retrieved source IDs;
- parameters where useful;
- trace/job ID.

This enables regression debugging and evals.

## 10. Prompt injection rule

Retrieved source text is never placed in privileged instruction channels. It is wrapped/serialized as evidence. Model requests must explicitly distinguish policy/system instructions from untrusted content.
