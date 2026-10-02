from __future__ import annotations

import base64
import json
import urllib.parse
from collections.abc import Mapping
from pathlib import Path
from uuid import UUID

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

from jmos_worker.contracts import ContractRegistry
from jmos_worker.drive import (
    FOLDER_MIME,
    MAX_FILES,
    TOKEN_URL,
    GoogleDriveClient,
    ServiceAccount,
    assert_allowed_url,
    load_service_account,
    signed_assertion,
    to_file_entry,
)
from jmos_worker.pipelines import build_handlers
from jmos_worker.queue import DriveSyncContext, JobError
from jmos_worker.runner import Worker
from tests.support import FakeQueue, make_job

CONNECTION = UUID("20000000-0000-4000-8000-0000000000dd")
ROOT = "1AbCdEfGhIjKlMnOpQrStUvWxYz_root"
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ACCOUNT = ServiceAccount(client_email="sync@project.iam.gserviceaccount.com", private_key=KEY)
DRIVE_PREFIX = "https://www.googleapis.com/drive/v3/"


def write_key(directory: Path, ref: str = "default", **overrides: object) -> Path:
    pem = KEY.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()
    document: dict[str, object] = {
        "type": "service_account",
        "client_email": ACCOUNT.client_email,
        "private_key": pem,
        **overrides,
    }
    path = directory / f"{ref}.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    return path


def _b64decode(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


class FakeDrive:
    """Answers the token endpoint and Drive v3 `files` calls from an in-memory folder tree."""

    def __init__(self, tree: Mapping[str, list[dict[str, object]]], page_size: int = 2) -> None:
        self.tree = tree
        self.page_size = page_size
        self.calls: list[tuple[str, str]] = []
        self.status_for: dict[str, tuple[int, dict[str, object]]] = {}

    def request(
        self, method: str, url: str, *, headers: Mapping[str, str], body: bytes | None
    ) -> tuple[int, bytes]:
        assert_allowed_url(url)
        self.calls.append((method, url))
        if url == TOKEN_URL:
            form = urllib.parse.parse_qs((body or b"").decode())
            assert form["grant_type"] == ["urn:ietf:params:oauth:grant-type:jwt-bearer"]
            return 200, json.dumps({"access_token": "token-1", "expires_in": 3600}).encode()
        assert headers["Authorization"] == "Bearer token-1"
        path, _, query = url.removeprefix(DRIVE_PREFIX).partition("?")
        if path in self.status_for:
            status, payload = self.status_for[path]
            return status, json.dumps(payload).encode()
        params = urllib.parse.parse_qs(query)
        if path != "files":
            item_id = path.removeprefix("files/")
            mime = FOLDER_MIME if item_id in self.tree else "application/pdf"
            return 200, json.dumps({"id": item_id, "mimeType": mime}).encode()
        parent = params["q"][0].split(" in parents")[0].strip("'")
        children = self.tree.get(parent, [])
        start = int(params.get("pageToken", ["0"])[0])
        page: dict[str, object] = {"files": children[start : start + self.page_size]}
        if start + self.page_size < len(children):
            page["nextPageToken"] = str(start + self.page_size)
        return 200, json.dumps(page).encode()


def drive_file(id_: str, name: str, revision: str = "r1", **extra: object) -> dict[str, object]:
    return {
        "id": id_,
        "name": name,
        "mimeType": "application/pdf",
        "headRevisionId": revision,
        **extra,
    }


def drive_folder(id_: str, name: str) -> dict[str, object]:
    return {"id": id_, "name": name, "mimeType": FOLDER_MIME}


TREE: dict[str, list[dict[str, object]]] = {
    ROOT: [
        drive_file("fileA0001", "Briefing.pdf", size="2048", md5Checksum="0" * 32),
        drive_folder("folderSub01", "Fotos"),
        drive_file("fileA0002", "Contrato.pdf"),
    ],
    "folderSub01": [
        drive_file("fileB0001", "Logo.png", modifiedTime="2026-10-02T12:00:00.000Z"),
        drive_file("fileA0001", "Briefing.pdf"),  # the same file in two folders appears once
    ],
}


# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
def test_credentials_resolve_inside_the_directory(tmp_path: Path) -> None:
    write_key(tmp_path)
    account = load_service_account(tmp_path, "default")
    assert account.client_email == ACCOUNT.client_email
    assert "PRIVATE" not in repr(account)


@pytest.mark.parametrize(
    ("configured", "ref", "code"),
    [
        (False, "default", "drive_credentials_missing"),
        (True, "outra", "drive_credentials_missing"),
        (True, "../default", "drive_credentials_invalid"),
        (True, "Default", "drive_credentials_invalid"),
    ],
)
def test_missing_or_malformed_credentials_fail_permanently(
    tmp_path: Path, configured: bool, ref: str, code: str
) -> None:
    write_key(tmp_path)
    with pytest.raises(JobError) as caught:
        load_service_account(tmp_path if configured else None, ref)
    assert caught.value.code == code
    assert caught.value.retryable is False


def test_a_key_file_that_is_not_a_service_account_is_refused(tmp_path: Path) -> None:
    write_key(tmp_path, type="authorized_user")
    with pytest.raises(JobError) as caught:
        load_service_account(tmp_path, "default")
    assert caught.value.code == "drive_credentials_invalid"


def test_the_assertion_is_a_signed_read_only_jwt() -> None:
    header, claims, signature = signed_assertion(ACCOUNT, 1_000_000).split(".")
    assert json.loads(_b64decode(header)) == {"alg": "RS256", "typ": "JWT"}
    payload = json.loads(_b64decode(claims))
    assert payload["scope"] == "https://www.googleapis.com/auth/drive.readonly"
    assert payload["aud"] == TOKEN_URL
    assert payload["exp"] - payload["iat"] == 3600
    KEY.public_key().verify(
        _b64decode(signature), f"{header}.{claims}".encode(), padding.PKCS1v15(), hashes.SHA256()
    )


# ---------------------------------------------------------------------------
# Snapshot
# ---------------------------------------------------------------------------
def test_snapshot_walks_the_tree_pages_and_deduplicates() -> None:
    drive = FakeDrive(TREE)
    beats: list[int] = []
    files = GoogleDriveClient(ACCOUNT, drive).snapshot(ROOT, lambda: beats.append(1))
    assert sorted(str(f["drive_file_id"]) for f in files) == ["fileA0001", "fileA0002", "fileB0001"]
    briefing = next(f for f in files if f["drive_file_id"] == "fileA0001")
    assert briefing["size_bytes"] == 2048
    assert briefing["md5_checksum"] == "0" * 32
    assert len(beats) >= 3  # the lease is extended after every page
    assert sum(1 for _, url in drive.calls if url == TOKEN_URL) == 1  # the token is reused


def test_snapshot_output_matches_the_job_contract() -> None:
    files = GoogleDriveClient(ACCOUNT, FakeDrive(TREE)).snapshot(ROOT, lambda: None)
    ContractRegistry.load_packaged().validate_output("drive.sync.v1", {"files": files})


def test_trashed_files_are_excluded_by_the_query() -> None:
    drive = FakeDrive(TREE)
    GoogleDriveClient(ACCOUNT, drive).snapshot(ROOT, lambda: None)
    listings = [url for _, url in drive.calls if "/files?" in url]
    assert listings
    assert all("trashed+%3D+false" in url for url in listings)


def test_a_file_id_is_not_a_folder() -> None:
    with pytest.raises(JobError) as caught:
        GoogleDriveClient(ACCOUNT, FakeDrive(TREE)).snapshot("fileA0001xx", lambda: None)
    assert caught.value.code == "drive_folder_invalid"


@pytest.mark.parametrize(
    ("status", "reason", "code", "retryable"),
    [
        (401, "", "drive_auth_failed", False),
        (403, "rateLimitExceeded", "drive_rate_limited", True),
        (403, "insufficientFilePermissions", "drive_access_denied", False),
        (404, "notFound", "drive_folder_not_found", False),
        (503, "", "drive_unavailable", True),
    ],
)
def test_drive_errors_map_to_failure_codes(
    status: int, reason: str, code: str, retryable: bool
) -> None:
    drive = FakeDrive(TREE)
    drive.status_for[f"files/{ROOT}"] = (status, {"error": {"errors": [{"reason": reason}]}})
    with pytest.raises(JobError) as caught:
        GoogleDriveClient(ACCOUNT, drive).snapshot(ROOT, lambda: None)
    assert (caught.value.code, caught.value.retryable) == (code, retryable)


def test_too_many_files_fail_permanently() -> None:
    big = {ROOT: [drive_file(f"file{index:06d}", f"F{index}") for index in range(MAX_FILES + 1)]}
    with pytest.raises(JobError) as caught:
        GoogleDriveClient(ACCOUNT, FakeDrive(big, page_size=1000)).snapshot(ROOT, lambda: None)
    assert caught.value.code == "too_many_files"


def test_only_google_endpoints_are_reachable() -> None:
    assert_allowed_url(DRIVE_PREFIX + "files")
    assert_allowed_url(TOKEN_URL)
    for url in (
        "http://www.googleapis.com/drive/v3/files",
        "https://www.googleapis.com.evil.test/drive/v3/files",
        "https://127.0.0.1/drive/v3/files",
        "https://www.googleapis.com/upload/drive/v3/files",
    ):
        with pytest.raises(JobError):
            assert_allowed_url(url)


def test_malformed_drive_items_are_skipped() -> None:
    assert to_file_entry({"id": "x1", "name": "  ", "mimeType": "a/b", "version": "1"}) is None
    assert to_file_entry({"id": "x1", "name": "a", "mimeType": "a/b"}) is None
    entry = to_file_entry(
        {"id": "x1", "name": "a", "mimeType": "a/b", "version": "7", "size": "-3"}
    )
    assert entry == {"drive_file_id": "x1", "name": "a", "mime_type": "a/b", "revision": "7"}


# ---------------------------------------------------------------------------
# Handler through the worker loop
# ---------------------------------------------------------------------------
def run_sync(tmp_path: Path, context: DriveSyncContext | None, drive: FakeDrive) -> FakeQueue:
    job = make_job("drive.sync.v1", {"connection_id": str(CONNECTION)})
    queue = FakeQueue([job])
    if context is not None:
        queue.drive_syncs[job.id] = context
    Worker(
        worker_id="unit-worker",
        queue=queue,
        handlers=build_handlers(
            None,
            drive_credentials_dir=tmp_path,
            drive_client_factory=lambda account: GoogleDriveClient(account, drive),
        ),
        contracts=ContractRegistry.load_packaged(),
        poll_interval_seconds=0.01,
        heartbeat_interval_seconds=60,
    ).run_once()
    return queue


SYNC = DriveSyncContext(connection_id=CONNECTION, root_folder_id=ROOT, credential_ref="default")


def test_the_sync_job_returns_the_snapshot(tmp_path: Path) -> None:
    write_key(tmp_path)
    queue = run_sync(tmp_path, SYNC, FakeDrive(TREE))
    (result,) = queue.completed.values()
    files = result["files"]
    assert isinstance(files, list)
    assert len(files) == 3


def test_a_sync_without_its_lease_reads_nothing(tmp_path: Path) -> None:
    write_key(tmp_path)
    drive = FakeDrive(TREE)
    queue = run_sync(tmp_path, None, drive)
    (error,) = queue.failed.values()
    assert error.code == "lease_lost"
    assert drive.calls == []


def test_a_sync_without_credentials_fails_visibly(tmp_path: Path) -> None:
    queue = run_sync(tmp_path, SYNC, FakeDrive(TREE))
    (error,) = queue.failed.values()
    assert (error.code, error.retryable) == ("drive_credentials_missing", False)
