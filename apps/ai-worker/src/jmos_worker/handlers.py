"""Job handlers, keyed by contract key (`type.vN`).

A handler receives already-validated input and returns output that is validated before it is
stored. Handlers must be safe to run more than once for the same job (at-least-once delivery):
domain side effects belong in the same transaction as completion (added with the first
domain-writing pipeline, Increment 3+).
"""

from __future__ import annotations

import json
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime

from jmos_worker.models import ModelAdapter, build_messages
from jmos_worker.queue import JobError, LeasedJob


@dataclass(frozen=True, slots=True)
class JobContext:
    job: LeasedJob
    worker_id: str
    worker_version: str
    # Long-running handlers call this between steps; False means the lease was lost and the
    # handler should stop (another attempt owns the job now).
    extend_lease: Callable[[], bool]


Handler = Callable[[JobContext, Mapping[str, object]], dict[str, object]]


def system_healthcheck_v1(context: JobContext, _payload: Mapping[str, object]) -> dict[str, object]:
    """Diagnostic round-trip with no domain side effects."""
    return {
        "worker_id": context.worker_id,
        "worker_version": context.worker_version,
        "checked_at": datetime.now(UTC).isoformat(),
    }


MODEL_CHECK_INSTRUCTIONS = (
    "You are a health check for a local model runtime. "
    'Reply with exactly this JSON object and nothing else: {"ok": true}'
)


def ai_model_check_v1(adapter: ModelAdapter) -> Handler:
    """Fixed-prompt round-trip through the model adapter (no domain side effects)."""

    def handle(context: JobContext, _payload: Mapping[str, object]) -> dict[str, object]:
        profile = context.job.model_profile
        if not profile:
            raise JobError(
                "model_profile_missing", "the job declares no model profile", retryable=False
            )
        reply = adapter.chat_json(
            profile, build_messages(MODEL_CHECK_INSTRUCTIONS, "Run the health check.")
        )
        try:
            answer = json.loads(reply.content)
        except ValueError:
            raise JobError(
                "model_output_invalid", "the model did not answer with JSON", retryable=False
            ) from None
        return {
            "model_profile": profile,
            "model": reply.model[:200],
            "latency_ms": max(reply.latency_ms, 0),
            "ok": isinstance(answer, dict) and answer.get("ok") is True,
        }

    return handle


# Handlers that need no model runtime.
DEFAULT_HANDLERS: Mapping[str, Handler] = {
    "system.healthcheck.v1": system_healthcheck_v1,
}


def build_handlers(adapter: ModelAdapter | None) -> dict[str, Handler]:
    """All handlers this worker can run; model jobs only when a model adapter is configured."""
    handlers = dict(DEFAULT_HANDLERS)
    if adapter is not None:
        handlers["ai.model_check.v1"] = ai_model_check_v1(adapter)
    return handlers
