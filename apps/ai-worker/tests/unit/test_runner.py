from __future__ import annotations

import threading
import time
from collections.abc import Mapping

import psycopg
import pytest

from jmos_worker.contracts import ContractRegistry
from jmos_worker.handlers import DEFAULT_HANDLERS, Handler, JobContext
from jmos_worker.queue import JobError, WorkerStatus
from jmos_worker.runner import Worker
from tests.support import FakeQueue, echo_registry, make_job


def build(
    queue: FakeQueue,
    handlers: Mapping[str, Handler] | None = None,
    contracts: ContractRegistry | None = None,
) -> Worker:
    return Worker(
        worker_id="unit-worker",
        queue=queue,
        handlers=handlers if handlers is not None else DEFAULT_HANDLERS,
        contracts=contracts if contracts is not None else ContractRegistry.load_packaged(),
        poll_interval_seconds=0.01,
        heartbeat_interval_seconds=60,
    )


def test_healthcheck_job_completes_with_a_contract_valid_result() -> None:
    job = make_job()
    queue = FakeQueue([job])

    assert build(queue).run_once() is True

    result = queue.completed[job.id]
    assert result["worker_id"] == "unit-worker"
    ContractRegistry.load_packaged().validate_output("system.healthcheck.v1", result)


def test_only_registered_job_types_are_requested() -> None:
    queue = FakeQueue()
    assert build(queue).run_once() is False
    assert queue.claimed_with == [["system.healthcheck.v1"]]


def test_invalid_input_fails_permanently_without_running_the_handler() -> None:
    calls: list[str] = []

    def echo(_ctx: JobContext, payload: Mapping[str, object]) -> dict[str, object]:
        calls.append("called")
        return dict(payload)

    job = make_job("test.echo.v1", {"text": "hi", "sql": "drop table jobs"})
    queue = FakeQueue([job])

    build(queue, {"test.echo.v1": echo}, echo_registry()).run_once()

    error = queue.failed[job.id]
    assert (error.code, error.retryable) == ("invalid_input", False)
    assert calls == []
    assert "drop table" not in error.message, "payload values must not leak into job errors"


def test_invalid_output_is_never_stored() -> None:
    def bad(_ctx: JobContext, _payload: Mapping[str, object]) -> dict[str, object]:
        return {"text": "x" * 50}

    job = make_job("test.echo.v1", {"text": "hi"})
    queue = FakeQueue([job])

    build(queue, {"test.echo.v1": bad}, echo_registry()).run_once()

    assert job.id not in queue.completed
    assert queue.failed[job.id].code == "invalid_output"


def test_handler_job_error_keeps_its_retry_decision() -> None:
    def flaky(_ctx: JobContext, _payload: Mapping[str, object]) -> dict[str, object]:
        raise JobError("model_unavailable", "model profile not loaded", retryable=True)

    job = make_job("test.echo.v1", {"text": "hi"})
    queue = FakeQueue([job])

    build(queue, {"test.echo.v1": flaky}, echo_registry()).run_once()

    assert (queue.failed[job.id].code, queue.failed[job.id].retryable) == (
        "model_unavailable",
        True,
    )


def test_unexpected_exception_is_recorded_as_retryable_without_its_message() -> None:
    def broken(_ctx: JobContext, _payload: Mapping[str, object]) -> dict[str, object]:
        raise RuntimeError("secret-token-123 leaked in message")

    job = make_job("test.echo.v1", {"text": "hi"})
    queue = FakeQueue([job])

    build(queue, {"test.echo.v1": broken}, echo_registry()).run_once()

    error = queue.failed[job.id]
    assert (error.code, error.retryable, error.message) == (
        "unhandled_exception",
        True,
        "RuntimeError",
    )


def test_handlers_must_have_a_contract() -> None:
    with pytest.raises(ValueError, match=r"test\.unknown\.v1"):
        build(FakeQueue(), {"test.unknown.v1": DEFAULT_HANDLERS["system.healthcheck.v1"]})


def test_graceful_shutdown_finishes_work_and_reports_stopped() -> None:
    job = make_job()
    queue = FakeQueue([job])
    worker = build(queue)

    thread = threading.Thread(target=worker.run)
    thread.start()
    deadline = time.monotonic() + 5
    while job.id not in queue.completed and time.monotonic() < deadline:
        time.sleep(0.01)
    worker.request_stop()
    thread.join(timeout=5)

    assert not thread.is_alive()
    assert job.id in queue.completed
    assert queue.heartbeats[0] is WorkerStatus.STARTING
    assert queue.heartbeats[-1] is WorkerStatus.STOPPED
    assert queue.closed


def test_database_outage_does_not_crash_the_loop() -> None:
    queue = FakeQueue()
    outages = iter([True, False])

    def maybe_fail() -> None:
        if next(outages, False):
            raise psycopg.OperationalError("connection refused")

    queue.on_claim = maybe_fail
    worker = build(queue)
    thread = threading.Thread(target=worker.run)
    thread.start()
    deadline = time.monotonic() + 5
    while len(queue.claimed_with) < 2 and time.monotonic() < deadline:
        time.sleep(0.01)
    worker.request_stop()
    thread.join(timeout=5)

    assert not thread.is_alive()
    assert len(queue.claimed_with) >= 2, "the worker must keep polling after an outage"
    assert queue.heartbeats[-1] is WorkerStatus.STOPPED


def test_database_outage_at_startup_is_retried_not_fatal() -> None:
    queue = FakeQueue([make_job()])
    failures = iter([True])

    def fail_first_start(status: WorkerStatus) -> None:
        if status is WorkerStatus.STARTING and next(failures, False):
            raise psycopg.OperationalError("database starting up")

    queue.on_heartbeat = fail_first_start
    worker = build(queue)
    thread = threading.Thread(target=worker.run)
    thread.start()
    deadline = time.monotonic() + 5
    while not queue.completed and time.monotonic() < deadline:
        time.sleep(0.01)
    worker.request_stop()
    thread.join(timeout=5)

    assert not thread.is_alive()
    assert len(queue.completed) == 1
    assert queue.heartbeats[0] is WorkerStatus.STARTING


def test_extending_a_lease_also_refreshes_liveness() -> None:
    def long_running(ctx: JobContext, payload: Mapping[str, object]) -> dict[str, object]:
        assert ctx.extend_lease() is True
        return dict(payload)

    job = make_job("test.echo.v1", {"text": "hi"})
    queue = FakeQueue([job])
    worker = Worker(
        worker_id="unit-worker",
        queue=queue,
        handlers={"test.echo.v1": long_running},
        contracts=echo_registry(),
        poll_interval_seconds=0.01,
        heartbeat_interval_seconds=0,
    )

    worker.run_once()

    assert queue.heartbeats.count(WorkerStatus.BUSY) >= 2
    assert job.id in queue.completed


def test_result_rejected_by_the_database_fails_permanently_instead_of_crashing() -> None:
    job = make_job()
    queue = FakeQueue([job])
    queue.complete_error = psycopg.errors.CheckViolation("jobs_result_check")

    assert build(queue).run_once() is True

    error = queue.failed[job.id]
    assert (error.code, error.retryable) == ("result_rejected", False)


def test_a_busy_worker_keeps_heartbeating_during_a_long_job() -> None:
    def slow(_ctx: JobContext, payload: Mapping[str, object]) -> dict[str, object]:
        time.sleep(0.35)
        return dict(payload)

    queue = FakeQueue([make_job("test.echo.v1", {"text": "hi"})])
    worker = Worker(
        worker_id="unit-worker",
        queue=queue,
        handlers={"test.echo.v1": slow},
        contracts=echo_registry(),
        poll_interval_seconds=0.01,
        heartbeat_interval_seconds=0.1,
    )
    worker.run_once()
    assert queue.heartbeats.count(WorkerStatus.BUSY) >= 3
