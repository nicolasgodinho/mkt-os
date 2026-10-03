"""Worker ↔ Postgres integration (docs/11 layer 4: queue execution, result application).

Run through `pnpm test:integration`, which provides:
  JMOS_TEST_DB_MODE              supabase | pglite
  JMOS_TEST_ADMIN_DATABASE_URL   owner connection used for fixtures and assertions
  JMOS_TEST_WORKER_DATABASE_URL  `jmos_worker` connection (supabase); the same superuser
                                 session in pglite, where role separation is covered by pgTAP
"""

from __future__ import annotations

import json
import os
import threading
import time
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path
from typing import cast
from uuid import UUID, uuid4

import psycopg
import pytest
from psycopg import sql
from psycopg.rows import dict_row

from jmos_worker import __version__
from jmos_worker.contracts import ContractRegistry
from jmos_worker.drive import GoogleDriveClient
from jmos_worker.handlers import DEFAULT_HANDLERS
from jmos_worker.models import ModelReply
from jmos_worker.pipelines import build_handlers
from jmos_worker.queue import CompletionOutcome, LeasedJob, PostgresJobQueue, WorkerRoleError
from jmos_worker.runner import Worker
from tests.unit.test_drive import ROOT as DRIVE_ROOT
from tests.unit.test_drive import TREE as DRIVE_TREE
from tests.unit.test_drive import FakeDrive, write_key

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


def test_concurrent_workers_never_share_a_lease(admin: AdminConnection, workspace_id: UUID) -> None:
    """FOR UPDATE SKIP LOCKED: every job is leased exactly once across competing workers.

    Real concurrency only exists in supabase mode; PGlite serializes the two sessions.
    """
    job_ids = [
        enqueue(admin, workspace_id, "system.healthcheck", f"it:{uuid4()}") for _ in range(20)
    ]
    workers = [make_worker(f"it-concurrent-{index}") for index in range(2)]

    def drain(worker: Worker) -> None:
        while worker.run_once():
            pass

    try:
        with ThreadPoolExecutor(max_workers=len(workers)) as pool:
            futures = [pool.submit(drain, worker) for worker, _ in workers]
            for future in futures:
                future.result(timeout=60)  # re-raises any exception from a worker thread
    finally:
        for _, queue in workers:
            queue.close()

    rows = [job_row(admin, job_id) for job_id in job_ids]
    assert all(row["status"] == "completed" for row in rows)
    assert all(row["attempts"] == 1 for row in rows), "a job was leased more than once"


class _ScriptedModel:
    """Stands in for the local model: always proposes one fact and one rule."""

    def chat_json(self, profile: str, messages: object) -> ModelReply:
        del profile, messages
        answer = {
            "proposals": [
                {"kind": "fact", "statement": "Atende três cidades.", "confidence": 0.9},
                {"kind": "rule", "rule_type": "MUST", "subject": "cta", "statement": "Use CTA."},
            ]
        }
        return ModelReply(content=json.dumps(answer), model="stub", latency_ms=1)


def test_meeting_extraction_writes_proposals_exactly_once(
    admin: AdminConnection, workspace_id: UUID
) -> None:
    client_id, source_id, meeting_id = uuid4(), uuid4(), uuid4()
    admin.execute(
        "insert into public.clients (id, workspace_id, name, slug) values (%s, %s, 'IT', %s)",
        (client_id, workspace_id, f"it-{client_id.hex[:12]}"),
    )
    admin.execute(
        "insert into public.sources (id, client_id, type, title, trust_level, created_by)"
        " select %s, %s, 'meeting', 'Reunião IT', 'FIRST_PARTY', id from public.users limit 1",
        (source_id, client_id),
    )
    admin.execute(
        "insert into public.meetings (id, client_id, title, starts_at, transcript_source_id)"
        " values (%s, %s, 'Reunião IT', now(), %s)",
        (meeting_id, client_id, source_id),
    )
    admin.execute(
        "insert into public.meeting_transcripts (meeting_id, revision, text, origin)"
        " values (%s, 1, 'Ana: atendemos três cidades.', 'manual')",
        (meeting_id,),
    )
    row = admin.execute(
        "select app.enqueue_job(%s, %s, 'meeting.extract', 1, %s, %s::jsonb, 100, 3, 'reasoning')",
        (
            workspace_id,
            client_id,
            f"it:{uuid4()}",
            json.dumps({"meeting_id": str(meeting_id), "transcript_revision": 1}),
        ),
    ).fetchone()
    assert row is not None
    job_id = cast(UUID, row[0])

    queue = PostgresJobQueue(
        env("JMOS_TEST_WORKER_DATABASE_URL"), worker_id="it-meeting", version="t", lease_seconds=60
    )
    worker = Worker(
        worker_id="it-meeting",
        queue=queue,
        handlers=build_handlers(_ScriptedModel()),
        contracts=ContractRegistry.load_packaged(),
        poll_interval_seconds=0.05,
        heartbeat_interval_seconds=5,
    )
    try:
        for _ in range(20):
            if job_row(admin, job_id)["status"] in TERMINAL:
                break
            worker.run_once()
        # A redelivered completion (e.g. the worker retried after a network error) is a no-op.
        job = LeasedJob(
            id=job_id,
            type="meeting.extract",
            schema_version=1,
            workspace_id=workspace_id,
            client_id=client_id,
            input={},
            attempt=1,
            max_attempts=3,
            lease_until=datetime.now(UTC),
            model_profile="reasoning",
            pipeline_version=None,
            trace_id=None,
        )
        assert queue.complete(job, {"proposals": []}) is CompletionOutcome.DUPLICATE

        assert job_row(admin, job_id)["status"] == "completed"
        proposals = admin.execute(
            "select kind::text, status::text from public.meeting_proposals"
            " where meeting_id = %s order by kind",
            (meeting_id,),
        ).fetchall()
        assert proposals == [("fact", "proposed"), ("rule", "proposed")]
        # Model output never became knowledge or rules by itself.
        assert admin.execute(
            "select count(*) from public.rules where client_id = %s", (client_id,)
        ).fetchone() == (0,)
    finally:
        queue.close()
        admin.execute("delete from public.meeting_proposals where meeting_id = %s", (meeting_id,))
        admin.execute("delete from public.meeting_transcripts where meeting_id = %s", (meeting_id,))
        admin.execute("delete from public.meetings where id = %s", (meeting_id,))
        admin.execute("delete from public.jobs where id = %s", (job_id,))
        admin.execute("delete from public.sources where id = %s", (source_id,))
        admin.execute("delete from public.clients where id = %s", (client_id,))


def test_drive_sync_applies_the_snapshot_once_and_schedules_the_next(
    admin: AdminConnection, workspace_id: UUID, tmp_path: Path
) -> None:
    client_id, connection_id = uuid4(), uuid4()
    admin.execute(
        "insert into public.clients (id, workspace_id, name, slug) values (%s, %s, 'IT', %s)",
        (client_id, workspace_id, f"it-{client_id.hex[:12]}"),
    )
    admin.execute(
        "insert into public.integration_connections"
        " (id, workspace_id, client_id, provider, root_folder_id, created_by)"
        " select %s, %s, %s, 'google_drive', %s, id from public.users limit 1",
        (connection_id, workspace_id, client_id, DRIVE_ROOT),
    )
    row = admin.execute(
        "select app.enqueue_job(%s, %s, 'drive.sync', 1, %s, %s::jsonb, 100)",
        (
            workspace_id,
            client_id,
            f"it:{uuid4()}",
            json.dumps({"connection_id": str(connection_id)}),
        ),
    ).fetchone()
    assert row is not None
    job_id = cast(UUID, row[0])
    write_key(tmp_path, workspace_id)

    queue = PostgresJobQueue(
        env("JMOS_TEST_WORKER_DATABASE_URL"), worker_id="it-drive", version="t", lease_seconds=60
    )
    worker = Worker(
        worker_id="it-drive",
        queue=queue,
        handlers=build_handlers(
            None,
            drive_credentials_dir=tmp_path,
            drive_client_factory=lambda account: GoogleDriveClient(account, FakeDrive(DRIVE_TREE)),
        ),
        contracts=ContractRegistry.load_packaged(),
        poll_interval_seconds=0.05,
        heartbeat_interval_seconds=5,
    )
    try:
        for _ in range(20):
            if job_row(admin, job_id)["status"] in TERMINAL:
                break
            worker.run_once()
        assert job_row(admin, job_id)["status"] == "completed"
        files = admin.execute(
            "select drive_file_id, sync_status::text, index_status::text from public.file_records"
            " where connection_id = %s order by drive_file_id",
            (connection_id,),
        ).fetchall()
        assert files == [
            ("fileA0001", "synced", "pending"),
            ("fileA0002", "synced", "pending"),
            ("fileB0001", "synced", "pending"),
        ]
        scheduled = admin.execute(
            "select count(*) from public.jobs where type = 'drive.sync' and status = 'queued'"
            " and run_after > now() and input ->> 'connection_id' = %s",
            (str(connection_id),),
        ).fetchone()
        assert scheduled == (1,)
    finally:
        queue.close()
        admin.execute("delete from public.file_records where connection_id = %s", (connection_id,))
        admin.execute("delete from public.jobs where client_id = %s", (client_id,))
        admin.execute("delete from public.integration_connections where id = %s", (connection_id,))
        admin.execute("delete from public.clients where id = %s", (client_id,))
