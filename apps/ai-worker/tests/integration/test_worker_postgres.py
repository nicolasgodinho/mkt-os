"""Worker ↔ Postgres integration (docs/11 layer 4: queue execution, result application).

Run through `pnpm test:integration`, which provides:
  JMOS_TEST_DB_MODE              supabase | pglite
  JMOS_TEST_ADMIN_DATABASE_URL   owner connection used for fixtures and assertions
  JMOS_TEST_WORKER_DATABASE_URL  `jmos_worker` connection (supabase); the same superuser
                                 session in pglite, where role separation is covered by pgTAP
"""

from __future__ import annotations

import os
import threading
import time
from collections.abc import Iterator
from typing import cast
from uuid import UUID, uuid4

import psycopg
import pytest
from psycopg import sql
from psycopg.rows import dict_row

from jmos_worker import __version__
from jmos_worker.contracts import ContractRegistry
from jmos_worker.handlers import DEFAULT_HANDLERS
from jmos_worker.queue import CompletionOutcome, PostgresJobQueue, WorkerRoleError
from jmos_worker.runner import Worker

pytestmark = pytest.mark.integration

AdminConnection = psycopg.Connection[tuple[object, ...]]
TERMINAL = {"completed", "failed", "dead_letter", "canceled"}


def env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        pytest.fail(f"{name} is not set; run integration tests with `pnpm test:integration`")
    return value


def supabase_only() -> None:
    if os.environ.get("JMOS_TEST_DB_MODE") != "supabase":
        pytest.skip("needs real role separation (JMOS_DB_MODE=supabase); pgTAP covers it in pglite")


@pytest.fixture
def admin() -> Iterator[AdminConnection]:
    with psycopg.connect(env("JMOS_TEST_ADMIN_DATABASE_URL"), autocommit=True) as conn:
        yield conn


@pytest.fixture
def workspace_id(admin: AdminConnection) -> Iterator[UUID]:
    workspace = uuid4()
    admin.execute(
        "insert into public.workspaces (id, name, slug) values (%s, %s, %s)",
        (workspace, "Integration", f"it-{workspace.hex[:12]}"),
    )
    yield workspace
    admin.execute("delete from public.jobs where workspace_id = %s", (workspace,))
    admin.execute("delete from public.workspaces where id = %s", (workspace,))
    admin.execute("delete from public.worker_heartbeats where worker_id like 'it-%'")


def enqueue(admin: AdminConnection, workspace: UUID, job_type: str, key: str) -> UUID:
    row = admin.execute(
        "select app.enqueue_job(%s::uuid, null, %s::text, 1, %s::text, '{}'::jsonb, 100)",
        (workspace, job_type, key),
    ).fetchone()
    assert row is not None
    return cast(UUID, row[0])


def job_row(admin: AdminConnection, job_id: UUID) -> dict[str, object]:
    with admin.cursor(row_factory=dict_row) as cur:
        cur.execute(
            "select status::text as status, attempts, result from public.jobs where id = %s",
            (job_id,),
        )
        row = cur.fetchone()
    assert row is not None
    return row


def make_worker(worker_id: str) -> tuple[Worker, PostgresJobQueue]:
    queue = PostgresJobQueue(
        env("JMOS_TEST_WORKER_DATABASE_URL"),
        worker_id=worker_id,
        version=__version__,
        lease_seconds=60,
    )
    worker = Worker(
        worker_id=worker_id,
        queue=queue,
        handlers=DEFAULT_HANDLERS,
        contracts=ContractRegistry.load_packaged(),
        poll_interval_seconds=0.05,
        heartbeat_interval_seconds=5,
    )
    return worker, queue


def test_healthcheck_job_runs_end_to_end(admin: AdminConnection, workspace_id: UUID) -> None:
    job_id = enqueue(admin, workspace_id, "system.healthcheck", f"it:{uuid4()}")
    worker, queue = make_worker("it-e2e")
    try:
        for _ in range(20):
            if job_row(admin, job_id)["status"] in TERMINAL:
                break
            worker.run_once()
    finally:
        queue.close()

    row = job_row(admin, job_id)
    assert (row["status"], row["attempts"]) == ("completed", 1)
    result = cast(dict[str, object], row["result"])
    assert result["worker_id"] == "it-e2e"
    ContractRegistry.load_packaged().validate_output("system.healthcheck.v1", result)


def test_duplicate_enqueue_and_redelivered_completion_have_one_effect(
    admin: AdminConnection, workspace_id: UUID
) -> None:
    key = f"it:{uuid4()}"
    first = enqueue(admin, workspace_id, "test.it_redelivery", key)
    assert enqueue(admin, workspace_id, "test.it_redelivery", key) == first

    queue = PostgresJobQueue(
        env("JMOS_TEST_WORKER_DATABASE_URL"),
        worker_id="it-redelivery",
        version="t",
        lease_seconds=60,
    )
    try:
        job = queue.claim(["test.it_redelivery.v1"])
        assert job is not None
        assert job.id == first
        assert queue.complete(job, {"n": 1}) is CompletionOutcome.COMPLETED
        assert queue.complete(job, {"n": 2}) is CompletionOutcome.DUPLICATE
    finally:
        queue.close()

    count = admin.execute(
        "select count(*) from public.jobs where workspace_id = %s and idempotency_key = %s",
        (workspace_id, key),
    ).fetchone()
    assert count == (1,)
    assert job_row(admin, first)["result"] == {"n": 1}


def test_graceful_shutdown_finishes_and_reports_stopped(
    admin: AdminConnection, workspace_id: UUID
) -> None:
    worker, _queue = make_worker("it-shutdown")
    thread = threading.Thread(target=worker.run)
    thread.start()
    try:
        job_id = enqueue(admin, workspace_id, "system.healthcheck", f"it:{uuid4()}")
        deadline = time.monotonic() + 15
        while job_row(admin, job_id)["status"] not in TERMINAL and time.monotonic() < deadline:
            time.sleep(0.05)
        assert job_row(admin, job_id)["status"] == "completed"
    finally:
        worker.request_stop()
        thread.join(timeout=15)

    assert not thread.is_alive()
    heartbeat = admin.execute(
        "select status::text from public.worker_heartbeats where worker_id = 'it-shutdown'"
    ).fetchone()
    assert heartbeat == ("stopped",)


def test_worker_refuses_a_role_that_can_bypass_the_worker_api() -> None:
    queue = PostgresJobQueue(
        env("JMOS_TEST_ADMIN_DATABASE_URL"), worker_id="it-priv", version="t", lease_seconds=60
    )
    try:
        with pytest.raises(WorkerRoleError):
            queue.assert_worker_role()
    finally:
        queue.close()


def test_worker_role_is_least_privilege() -> None:
    supabase_only()
    queue = PostgresJobQueue(
        env("JMOS_TEST_WORKER_DATABASE_URL"), worker_id="it-least", version="t", lease_seconds=60
    )
    try:
        queue.assert_worker_role()
    finally:
        queue.close()

    with psycopg.connect(env("JMOS_TEST_WORKER_DATABASE_URL"), autocommit=True) as conn:
        for table in ("jobs", "clients", "workspace_memberships"):
            query = sql.SQL("select 1 from {}").format(sql.Identifier("public", table))
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                conn.execute(query)
