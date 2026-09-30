"""Access to the durable job queue through the narrow `worker.*` SQL API.

Delivery is at-least-once: a job may be delivered again after a crash or an expired lease.
Every write is fenced by (worker_id, attempt), so a stale worker can never overwrite a newer
attempt. The worker role has no table privileges, only EXECUTE on the `worker` functions.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Protocol
from uuid import UUID

import psycopg
from psycopg.rows import class_row, dict_row
from psycopg.types.json import Jsonb


@dataclass(frozen=True, slots=True)
class LeasedJob:
    """A job leased by this worker. `attempt` is the fencing token for every later write."""

    id: UUID
    type: str
    schema_version: int
    workspace_id: UUID
    client_id: UUID | None
    input: dict[str, object]
    attempt: int
    max_attempts: int
    lease_until: datetime
    model_profile: str | None
    pipeline_version: str | None
    trace_id: str | None

    @property
    def contract_key(self) -> str:
        return f"{self.type}.v{self.schema_version}"


class CompletionOutcome(StrEnum):
    COMPLETED = "completed"
    DUPLICATE = "duplicate"  # already completed (redelivery); nothing changed
    LEASE_LOST = "lease_lost"  # lease reclaimed by another attempt; nothing changed


class FailureOutcome(StrEnum):
    RETRY_SCHEDULED = "retry_scheduled"
    DEAD_LETTER = "dead_letter"
    FAILED = "failed"
    LEASE_LOST = "lease_lost"


class WorkerStatus(StrEnum):
    STARTING = "starting"
    IDLE = "idle"
    BUSY = "busy"
    STOPPING = "stopping"
    STOPPED = "stopped"


class JobError(Exception):
    """Raised by handlers. `retryable` chooses between retry/backoff and permanent failure."""

    MAX_MESSAGE = 500

    def __init__(self, code: str, message: str, *, retryable: bool) -> None:
        super().__init__(message)
        self.code = code
        self.message = message[: self.MAX_MESSAGE]
        self.retryable = retryable

    def to_payload(self) -> dict[str, object]:
        return {"code": self.code, "message": self.message, "retryable": self.retryable}


class WorkerRoleError(RuntimeError):
    """The database role is not the narrow worker role: over-privileged or unable to use the API."""


class JobQueue(Protocol):
    def claim(self, job_types: Sequence[str]) -> LeasedJob | None: ...

    def complete(self, job: LeasedJob, result: Mapping[str, object]) -> CompletionOutcome: ...

    def fail(self, job: LeasedJob, error: JobError) -> FailureOutcome: ...

    def extend_lease(self, job: LeasedJob) -> bool: ...

    def heartbeat(self, status: WorkerStatus, job_types: Sequence[str]) -> None: ...

    def close(self) -> None: ...


class PostgresJobQueue:
    """JobQueue over one autocommit connection: each call is a single atomic SQL function call."""

    def __init__(
        self, database_url: str, *, worker_id: str, version: str, lease_seconds: int
    ) -> None:
        self._database_url = database_url
        self._worker_id = worker_id
        self._version = version
        self._lease_seconds = lease_seconds
        self._conn: psycopg.Connection[tuple[object, ...]] | None = None

    def _connection(self) -> psycopg.Connection[tuple[object, ...]]:
        if self._conn is None or self._conn.closed or self._conn.broken:
            self.close()
            self._conn = psycopg.connect(
                self._database_url,
                autocommit=True,
                connect_timeout=10,
                application_name=f"jmos-worker:{self._worker_id}",
                # No server-side prepared statements: they break behind transaction-mode poolers
                # (e.g. Supabase's pooler) and the calls are cheap single-function statements.
                prepare_threshold=None,
            )
        return self._conn

    def assert_worker_role(self) -> None:
        """Requires the least-privileged worker role (docs/05 §1): it must be able to use the worker
        API and must NOT be able to bypass it (superuser, BYPASSRLS or direct table access)."""
        with self._connection().cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                select current_user::text as role,
                       r.rolsuper as is_superuser,
                       r.rolbypassrls as bypasses_rls,
                       has_table_privilege('public.jobs', 'SELECT') as reads_jobs_table,
                       has_function_privilege('worker.claim_job(text, text[], integer)', 'EXECUTE')
                         as uses_worker_api
                  from pg_roles r
                 where r.rolname = current_user
                """
            )
            row = cur.fetchone()
        if row is None:
            raise WorkerRoleError("could not inspect the current database role")
        if not row["uses_worker_api"]:
            raise WorkerRoleError(
                f"database role {row['role']!r} cannot execute the worker API; "
                "connect as the `jmos_worker` role (see apps/ai-worker/README.md)"
            )
        if row["is_superuser"] or row["bypasses_rls"] or row["reads_jobs_table"]:
            raise WorkerRoleError(
                f"database role {row['role']!r} is too privileged for the AI Worker; "
                "connect as the `jmos_worker` role (see apps/ai-worker/README.md)"
            )

    def claim(self, job_types: Sequence[str]) -> LeasedJob | None:
        with self._connection().cursor(row_factory=class_row(LeasedJob)) as cur:
            cur.execute(
                "select * from worker.claim_job(%s, %s, %s)",
                (self._worker_id, list(job_types), self._lease_seconds),
            )
            return cur.fetchone()

    def complete(self, job: LeasedJob, result: Mapping[str, object]) -> CompletionOutcome:
        value = self._scalar(
            "select worker.complete_job(%s, %s, %s, %s)",
            (job.id, self._worker_id, job.attempt, Jsonb(dict(result))),
        )
        return CompletionOutcome(str(value))

    def fail(self, job: LeasedJob, error: JobError) -> FailureOutcome:
        value = self._scalar(
            "select worker.fail_job(%s, %s, %s, %s, %s)",
            (job.id, self._worker_id, job.attempt, Jsonb(error.to_payload()), error.retryable),
        )
        return FailureOutcome(str(value))

    def extend_lease(self, job: LeasedJob) -> bool:
        value = self._scalar(
            "select worker.extend_lease(%s, %s, %s, %s)",
            (job.id, self._worker_id, job.attempt, self._lease_seconds),
        )
        return value is True

    def heartbeat(self, status: WorkerStatus, job_types: Sequence[str]) -> None:
        self._connection().execute(
            "select worker.heartbeat(%s, %s, %s, %s)",
            (self._worker_id, status.value, self._version, list(job_types)),
        )

    def close(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None

    def _scalar(self, sql: str, params: Sequence[object]) -> object:
        row = self._connection().execute(sql, params).fetchone()
        if row is None:
            raise RuntimeError(f"no result from: {sql}")
        return row[0]
