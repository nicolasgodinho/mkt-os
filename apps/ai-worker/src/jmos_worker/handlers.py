"""Job handlers, keyed by contract key (`type.vN`).

A handler receives already-validated input and returns output that is validated before it is
stored. Handlers must be safe to run more than once for the same job (at-least-once delivery):
domain side effects belong in the same transaction as completion (added with the first
domain-writing pipeline, Increment 3+).
"""

from __future__ import annotations

from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime

from jmos_worker.queue import LeasedJob


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


DEFAULT_HANDLERS: Mapping[str, Handler] = {
    "system.healthcheck.v1": system_healthcheck_v1,
}
