"""The worker loop: lease → validate → execute → validate → complete/fail.

Failure handling:
  * JobError from a handler: recorded with its own retryable flag.
  * Any other handler exception: recorded as retryable `unhandled_exception` and logged with
    its traceback locally. The traceback never goes to the database.
  * Database unavailable: logged, then retried with capped backoff. The loop does not exit, and
    an in-flight job's lease expires so the job is redelivered (at-least-once).
Graceful shutdown: `request_stop()` lets the current job finish, stops leasing, and marks the
worker `stopped`.
"""

from __future__ import annotations

import logging
import threading
import time
from collections.abc import Callable, Mapping

import psycopg

from jmos_worker import __version__
from jmos_worker.contracts import ContractRegistry
from jmos_worker.handlers import Handler, JobContext
from jmos_worker.queue import (
    CompletionOutcome,
    FailureOutcome,
    JobError,
    JobQueue,
    LeasedJob,
    WorkerStatus,
)

logger = logging.getLogger("jmos_worker")

MAX_DB_BACKOFF_SECONDS = 60.0


class Worker:
    def __init__(
        self,
        *,
        worker_id: str,
        queue: JobQueue,
        handlers: Mapping[str, Handler],
        contracts: ContractRegistry,
        poll_interval_seconds: float,
        heartbeat_interval_seconds: float,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        missing = sorted(set(handlers) - contracts.contract_keys())
        if missing:
            raise ValueError(f"handlers without a job contract: {missing}")
        self._worker_id = worker_id
        self._queue = queue
        self._handlers = dict(handlers)
        self._contracts = contracts
        self._job_types = sorted(self._handlers)
        self._poll_interval = poll_interval_seconds
        self._heartbeat_interval = heartbeat_interval_seconds
        self._clock = clock
        self._stop = threading.Event()
        self._last_heartbeat: float | None = None

    @property
    def job_types(self) -> list[str]:
        return list(self._job_types)

    def request_stop(self) -> None:
        self._stop.set()

    @property
    def stopping(self) -> bool:
        return self._stop.is_set()

    def run(self) -> None:
        log_context = {"worker_id": self._worker_id}
        logger.info(
            "worker starting (job types: %s)", ", ".join(self._job_types), extra=log_context
        )
        db_failures = 0
        announced = False
        try:
            while not self._stop.is_set():
                try:
                    if not announced:
                        self._heartbeat(WorkerStatus.STARTING, force=True)
                        announced = True
                    processed = self.run_once()
                    self._heartbeat(WorkerStatus.IDLE)
                    db_failures = 0
                except psycopg.OperationalError:
                    db_failures += 1
                    delay = min(self._poll_interval * 2**db_failures, MAX_DB_BACKOFF_SECONDS)
                    logger.exception(
                        "database unavailable; retrying in %.1fs", delay, extra=log_context
                    )
                    self._stop.wait(delay)
                    continue
                if not processed:
                    self._stop.wait(self._poll_interval)
        finally:
            self._shutdown()

    def run_once(self) -> bool:
        """Leases and processes at most one job. Returns False when nothing was due."""
        job = self._queue.claim(self._job_types)
        if job is None:
            return False
        self._heartbeat(WorkerStatus.BUSY, force=True)
        self._process(job)
        return True

    def _process(self, job: LeasedJob) -> None:
        context: dict[str, object] = {
            "worker_id": self._worker_id,
            "trace_id": job.trace_id,
            "workspace_id": job.workspace_id,
            "client_id": job.client_id,
            "job_id": job.id,
            "job_type": job.contract_key,
            "attempt": job.attempt,
        }
        started = self._clock()
        logger.info("job leased", extra=context)
        try:
            handler = self._handlers.get(job.contract_key)
            if handler is None:
                raise JobError(
                    "unknown_job_type", f"no handler for {job.contract_key}", retryable=False
                )
            self._contracts.validate_input(job.contract_key, job.input)
            output = handler(self._job_context(job), job.input)
            self._contracts.validate_output(job.contract_key, output)
        except JobError as error:
            self._record_failure(job, error, context, started)
        except psycopg.OperationalError:
            # Losing the database mid-job is not the job's fault: let the lease expire and the
            # job be redelivered; the run loop handles reconnection.
            raise
        except Exception as error:  # any handler bug becomes a recorded, logged job failure
            logger.exception("handler raised an unexpected exception", extra=context)
            self._record_failure(
                job,
                JobError("unhandled_exception", type(error).__name__, retryable=True),
                context,
                started,
            )
        else:
            outcome = self._queue.complete(job, output)
            level = logging.INFO if outcome is CompletionOutcome.COMPLETED else logging.WARNING
            logger.log(
                level,
                "job finished",
                extra={**context, "outcome": outcome.value, "duration_ms": self._elapsed(started)},
            )

    def _record_failure(
        self, job: LeasedJob, error: JobError, context: Mapping[str, object], started: float
    ) -> None:
        outcome = self._queue.fail(job, error)
        level = logging.WARNING if outcome is FailureOutcome.RETRY_SCHEDULED else logging.ERROR
        logger.log(
            level,
            "job failed: %s",
            error.message,
            extra={
                **context,
                "outcome": outcome.value,
                "error_code": error.code,
                "duration_ms": self._elapsed(started),
            },
        )

    def _job_context(self, job: LeasedJob) -> JobContext:
        return JobContext(
            job=job,
            worker_id=self._worker_id,
            worker_version=__version__,
            extend_lease=lambda: self._extend_lease(job),
        )

    def _extend_lease(self, job: LeasedJob) -> bool:
        # Long jobs extend their lease between steps; keep the liveness row fresh at the same time.
        self._heartbeat(WorkerStatus.BUSY)
        return self._queue.extend_lease(job)

    def _heartbeat(self, status: WorkerStatus, *, force: bool = False) -> None:
        now = self._clock()
        due = self._last_heartbeat is None or now - self._last_heartbeat >= self._heartbeat_interval
        if force or due:
            self._queue.heartbeat(status, self._job_types)
            self._last_heartbeat = now

    def _shutdown(self) -> None:
        log_context = {"worker_id": self._worker_id}
        try:
            self._queue.heartbeat(WorkerStatus.STOPPED, self._job_types)
        except psycopg.OperationalError:
            logger.warning(
                "could not record the stopped heartbeat; the worker will appear offline once "
                "its heartbeat goes stale",
                exc_info=True,
                extra=log_context,
            )
        finally:
            self._queue.close()
            logger.info("worker stopped", extra=log_context)

    def _elapsed(self, started: float) -> int:
        return round((self._clock() - started) * 1000)
