"""Test doubles shared by the worker test suites."""

from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from jmos_worker.contracts import ContractRegistry, packaged_documents
from jmos_worker.queue import (
    CompletionOutcome,
    FailureOutcome,
    JobError,
    LeasedJob,
    MeetingContext,
    WorkerStatus,
)

WORKSPACE_ID = UUID("f1000000-0000-4000-8000-000000000001")


def make_job(
    contract_key: str = "system.healthcheck.v1",
    payload: dict[str, object] | None = None,
    *,
    model_profile: str | None = None,
) -> LeasedJob:
    type_, _, version = contract_key.rpartition(".v")
    return LeasedJob(
        id=uuid4(),
        type=type_,
        schema_version=int(version),
        workspace_id=WORKSPACE_ID,
        client_id=None,
        input=payload if payload is not None else {},
        attempt=1,
        max_attempts=3,
        lease_until=datetime.now(UTC) + timedelta(minutes=5),
        model_profile=model_profile,
        pipeline_version=None,
        trace_id="trace-test",
    )


ECHO_SCHEMA: dict[str, object] = {
    "type": "object",
    "properties": {"text": {"type": "string", "maxLength": 20}},
    "required": ["text"],
    "additionalProperties": False,
}


def echo_registry() -> ContractRegistry:
    """Packaged contracts plus `test.echo.v1`: input and output are {text: str}."""
    echo = {"type": "test.echo", "schema_version": 1, "input": ECHO_SCHEMA, "output": ECHO_SCHEMA}
    return ContractRegistry.from_documents([*packaged_documents(), echo])


class FakeQueue:
    """In-memory JobQueue with the same duplicate/fencing outcomes as the SQL API."""

    def __init__(self, jobs: Sequence[LeasedJob] = ()) -> None:
        self.pending = list(jobs)
        self.completed: dict[UUID, dict[str, object]] = {}
        self.failed: dict[UUID, JobError] = {}
        self.heartbeats: list[WorkerStatus] = []
        self.model_profiles: list[str | None] = []
        self.claimed_with: list[list[str]] = []
        self.closed = False
        self.on_claim: Callable[[], None] | None = None
        self.on_heartbeat: Callable[[WorkerStatus], None] | None = None
        self.complete_error: Exception | None = None
        self.meetings: dict[UUID, MeetingContext] = {}

    def claim(self, job_types: Sequence[str]) -> LeasedJob | None:
        self.claimed_with.append(list(job_types))
        if self.on_claim is not None:
            self.on_claim()
        for index, job in enumerate(self.pending):
            if job.contract_key in job_types:
                return self.pending.pop(index)
        return None

    def complete(self, job: LeasedJob, result: Mapping[str, object]) -> CompletionOutcome:
        if self.complete_error is not None:
            raise self.complete_error
        if job.id in self.completed:
            return CompletionOutcome.DUPLICATE
        self.completed[job.id] = dict(result)
        return CompletionOutcome.COMPLETED

    def fail(self, job: LeasedJob, error: JobError) -> FailureOutcome:
        self.failed[job.id] = error
        return FailureOutcome.RETRY_SCHEDULED if error.retryable else FailureOutcome.FAILED

    def extend_lease(self, job: LeasedJob) -> bool:
        return job.id not in self.completed

    def heartbeat(
        self,
        status: WorkerStatus,
        job_types: Sequence[str],
        active_model_profile: str | None = None,
    ) -> None:
        if self.on_heartbeat is not None:
            self.on_heartbeat(status)
        self.heartbeats.append(status)
        self.model_profiles.append(active_model_profile)

    def meeting_for_job(self, job: LeasedJob) -> MeetingContext | None:
        return self.meetings.get(job.id)

    def close(self) -> None:
        self.closed = True
