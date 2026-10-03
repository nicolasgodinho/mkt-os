"""Google Drive sync (docs/09 "Drive connector"; ADR 0004).

The worker lists the files under a client's Drive folder and returns a metadata snapshot; the
database applies it in the job's completion transaction. File contents are never downloaded.

Boundary rules (ADR 0004):
* Credentials are *references*: `credential_ref` names a service-account key file inside
  `JMOS_DRIVE_CREDENTIALS_DIR`. Keys and tokens never reach the database, jobs, logs or results.
* Read-only scope, and outbound requests only to the Google token endpoint and the Drive v3 API,
  over HTTPS, without redirects or proxies, with bounded response sizes.
* Drive names and metadata are untrusted data: they are stored, never interpreted.
"""

from __future__ import annotations

import base64
import http.client
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import deque
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, cast
from uuid import UUID

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

from jmos_worker.handlers import Handler, JobContext
from jmos_worker.queue import DriveSyncContext, JobError

TOKEN_URL = "https://oauth2.googleapis.com/token"  # noqa: S105 (an endpoint, not a secret)
DRIVE_API = "https://www.googleapis.com/drive/v3/"
# (scheme, host, path, prefix?): checked on the parsed URL, never by string prefix alone. The
# token endpoint is one exact path; the Drive API is a path prefix.
ALLOWED_ENDPOINTS = (
    ("https", "oauth2.googleapis.com", "/token", False),
    ("https", "www.googleapis.com", "/drive/v3/", True),
)
SCOPE = "https://www.googleapis.com/auth/drive.readonly"
FOLDER_MIME = "application/vnd.google-apps.folder"

MAX_FILES = 5000  # the drive.sync v1 output limit
MAX_FOLDERS = 2000
MAX_DEPTH = 20
MAX_RESPONSE_BYTES = 10_000_000
PAGE_SIZE = 1000
# Pages a full listing can legitimately need, with headroom; more means Drive is looping.
MAX_PAGES = MAX_FOLDERS + 4 * (MAX_FILES // PAGE_SIZE + 1)
# Characters that are invisible or reorder text (bidi overrides, isolates): they can disguise a
# file name's extension, so they are removed before names are stored or shown.
UNSAFE_NAME_CHARACTERS = re.compile(r"[\x00-\x1f\x7f​-‏‪-‮⁦-⁩﻿\ud800-\udfff]")

CREDENTIAL_REF = re.compile(r"^[a-z0-9_]{1,40}$")
DRIVE_ID = re.compile(r"^[A-Za-z0-9_-]{1,200}$")
MD5 = re.compile(r"^[a-f0-9]{32}$")
FILE_FIELDS = "id,name,mimeType,md5Checksum,size,modifiedTime,headRevisionId,version"


# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
@dataclass(frozen=True, slots=True)
class ServiceAccount:
    client_email: str
    private_key: rsa.RSAPrivateKey

    def __repr__(self) -> str:  # never print key material
        return f"ServiceAccount(client_email={self.client_email!r})"


def load_service_account(
    credentials_dir: Path | None, workspace_id: UUID, credential_ref: str
) -> ServiceAccount:
    """Resolves a credential reference to `<dir>/<workspace id>/<ref>.json`.

    Keys are bound to the workspace of the leased job (ADR 0004): a connection in one workspace
    can never use a key kept for another, whatever reference it names.
    """
    if credentials_dir is None:
        raise JobError(
            "drive_credentials_missing",
            "JMOS_DRIVE_CREDENTIALS_DIR is not configured on this worker",
            retryable=False,
        )
    if not CREDENTIAL_REF.match(credential_ref):
        raise JobError(
            "drive_credentials_invalid", "the credential reference is malformed", retryable=False
        )
    root = (credentials_dir / str(workspace_id)).resolve()
    path = (root / f"{credential_ref}.json").resolve()
    if path.parent != root or not path.is_file():
        raise JobError(
            "drive_credentials_missing",
            f"no key file for credential reference {credential_ref!r}",
            retryable=False,
        )
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
        email = document["client_email"]
        pem = document["private_key"]
        if document.get("type") != "service_account" or not isinstance(email, str):
            raise ValueError("not a service account")
        key = serialization.load_pem_private_key(pem.encode("utf-8"), password=None)
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        raise JobError(
            "drive_credentials_invalid",
            f"the key file for {credential_ref!r} is not a valid service-account key",
            retryable=False,
        ) from None
    if not isinstance(key, rsa.RSAPrivateKey):
        raise JobError(
            "drive_credentials_invalid",
            "the service-account key is not an RSA key",
            retryable=False,
        )
    return ServiceAccount(client_email=email, private_key=key)


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def signed_assertion(account: ServiceAccount, now: float) -> str:
    """A JWT bearer assertion (RFC 7523) for Google's OAuth token endpoint."""
    header = _b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    issued = int(now)
    claims = _b64url(
        json.dumps(
            {
                "iss": account.client_email,
                "scope": SCOPE,
                "aud": TOKEN_URL,
                "iat": issued,
                "exp": issued + 3600,
            }
        ).encode()
    )
    signing_input = f"{header}.{claims}".encode("ascii")
    signature = account.private_key.sign(signing_input, padding.PKCS1v15(), hashes.SHA256())
    return f"{header}.{claims}.{_b64url(signature)}"


# ---------------------------------------------------------------------------
# HTTP transport: allow-listed, no redirects, no proxies, bounded
# ---------------------------------------------------------------------------
class Transport(Protocol):
    def request(
        self, method: str, url: str, *, headers: Mapping[str, str], body: bytes | None
    ) -> tuple[int, bytes]: ...


def assert_allowed_url(url: str) -> None:
    parts = urllib.parse.urlsplit(url)
    path = parts.path
    allowed = (
        parts.username is None
        and parts.password is None
        and parts.port is None
        # No dot segments, raw or percent-encoded: the path must be exactly what was checked.
        and ".." not in path
        and "%2e" not in path.lower()
        and any(
            parts.scheme == scheme
            and parts.hostname == host
            and (path.startswith(allowed_path) if prefix else path == allowed_path)
            for scheme, host, allowed_path, prefix in ALLOWED_ENDPOINTS
        )
    )
    if not allowed:
        raise JobError("drive_url_refused", "outbound URL is not allow-listed", retryable=False)


class _RefuseRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: object,
        code: int,
        msg: str,
        headers: object,
        newurl: str,
    ) -> None:
        del req, fp, code, msg, headers, newurl


class UrllibTransport:
    def __init__(self, *, timeout_seconds: float) -> None:
        self._timeout = timeout_seconds
        self._opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), _RefuseRedirects()
        )

    def request(
        self, method: str, url: str, *, headers: Mapping[str, str], body: bytes | None
    ) -> tuple[int, bytes]:
        assert_allowed_url(url)
        request = urllib.request.Request(  # noqa: S310 (allow-listed https URLs only)
            url, data=body, headers=dict(headers), method=method
        )
        try:
            with self._opener.open(request, timeout=self._timeout) as response:
                return int(response.status), _read_bounded(response)
        except urllib.error.HTTPError as error:
            return int(error.code), _read_bounded(error)
        except (
            urllib.error.URLError,
            http.client.HTTPException,
            TimeoutError,
            ConnectionError,
            OSError,
        ):
            raise JobError(
                "drive_unavailable", "Google Drive is not reachable", retryable=True
            ) from None


def _read_bounded(response: object) -> bytes:
    reader = cast(Callable[[int], bytes], getattr(response, "read"))  # noqa: B009
    data = reader(MAX_RESPONSE_BYTES + 1)
    if len(data) > MAX_RESPONSE_BYTES:
        raise JobError("drive_response_too_large", "Drive answer is too large", retryable=False)
    return data


# ---------------------------------------------------------------------------
# Drive client
# ---------------------------------------------------------------------------
def _json(body: bytes) -> dict[str, object]:
    try:
        value = json.loads(body)
    except ValueError:
        raise JobError(
            "drive_unexpected", "Drive returned a non-JSON body", retryable=False
        ) from None
    if not isinstance(value, dict):
        raise JobError("drive_unexpected", "Drive returned an unexpected body", retryable=False)
    return cast(dict[str, object], value)


def _api_error(status: int, body: bytes) -> JobError:
    reason = ""
    try:
        errors = cast(dict[str, object], json.loads(body).get("error", {})).get("errors", [])
        if isinstance(errors, list) and errors and isinstance(errors[0], dict):
            reason = str(errors[0].get("reason", ""))
    except (ValueError, AttributeError):
        reason = ""
    if status == 401:
        return JobError("drive_auth_failed", "Google rejected the credentials", retryable=False)
    if status == 403 and reason in ("rateLimitExceeded", "userRateLimitExceeded"):
        return JobError("drive_rate_limited", "Drive rate limit reached", retryable=True)
    if status == 403:
        return JobError(
            "drive_access_denied", "the folder is not shared with the account", retryable=False
        )
    if status == 404:
        return JobError("drive_folder_not_found", "the Drive folder was not found", retryable=False)
    if status == 429 or status >= 500:
        return JobError("drive_unavailable", f"Drive answered HTTP {status}", retryable=True)
    return JobError("drive_unexpected", f"Drive answered HTTP {status}", retryable=False)


class GoogleDriveClient:
    def __init__(
        self,
        account: ServiceAccount,
        transport: Transport,
        *,
        clock: Callable[[], float] = time.time,
    ) -> None:
        self._account = account
        self._transport = transport
        self._clock = clock
        self._token: str | None = None
        self._token_expires = 0.0

    def _access_token(self) -> str:
        now = self._clock()
        if self._token is not None and now < self._token_expires - 60:
            return self._token
        body = urllib.parse.urlencode(
            {
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": signed_assertion(self._account, now),
            }
        ).encode("ascii")
        status, raw = self._transport.request(
            "POST",
            TOKEN_URL,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            body=body,
        )
        if status in (400, 401, 403):
            raise JobError("drive_auth_failed", "Google rejected the credentials", retryable=False)
        if status != 200:
            raise _api_error(status, raw)
        payload = _json(raw)
        token = payload.get("access_token")
        expires_in = payload.get("expires_in", 3600)
        if not isinstance(token, str) or not token:
            raise JobError("drive_auth_failed", "Google returned no access token", retryable=False)
        self._token = token
        self._token_expires = now + (float(expires_in) if isinstance(expires_in, int) else 3600.0)
        return token

    def _get(self, path: str, params: Mapping[str, str]) -> dict[str, object]:
        url = DRIVE_API + path + "?" + urllib.parse.urlencode(params)
        status, raw = self._transport.request(
            "GET", url, headers={"Authorization": f"Bearer {self._access_token()}"}, body=None
        )
        if status != 200:
            raise _api_error(status, raw)
        return _json(raw)

    def snapshot(
        self, root_folder_id: str, keep_lease: Callable[[], None]
    ) -> list[dict[str, object]]:
        """Every file (not folder) under the folder tree, as drive.sync v1 file entries."""
        if not DRIVE_ID.match(root_folder_id):
            raise JobError("drive_folder_not_found", "the folder id is malformed", retryable=False)
        root = self._get(
            f"files/{root_folder_id}", {"fields": "id,mimeType", "supportsAllDrives": "true"}
        )
        if root.get("mimeType") != FOLDER_MIME:
            raise JobError("drive_folder_invalid", "the Drive id is not a folder", retryable=False)

        files: dict[str, dict[str, object]] = {}
        folders: deque[tuple[str, int]] = deque([(root_folder_id, 0)])
        visited = {root_folder_id}
        pages = 0
        while folders:
            folder_id, depth = folders.popleft()
            page_token: str | None = None
            while True:
                params = {
                    # folder ids are validated against DRIVE_ID, so they cannot break the query.
                    "q": f"'{folder_id}' in parents and trashed = false",
                    "fields": f"nextPageToken,files({FILE_FIELDS})",
                    "pageSize": str(PAGE_SIZE),
                    "supportsAllDrives": "true",
                    "includeItemsFromAllDrives": "true",
                }
                if page_token is not None:
                    params["pageToken"] = page_token
                pages += 1
                if pages > MAX_PAGES:
                    raise JobError(
                        "drive_listing_too_long",
                        "Drive kept returning pages; the listing was stopped",
                        retryable=True,
                    )
                page = self._get("files", params)
                for item in cast(list[object], page.get("files") or []):
                    if not isinstance(item, dict):
                        continue
                    entry = cast(dict[str, object], item)
                    item_id = entry.get("id")
                    if not isinstance(item_id, str) or not DRIVE_ID.match(item_id):
                        continue
                    if entry.get("mimeType") == FOLDER_MIME:
                        # Skipping a deeper folder would make its files look removed: refuse.
                        if depth + 1 > MAX_DEPTH:
                            raise JobError(
                                "folder_tree_too_deep",
                                f"the folder tree is deeper than {MAX_DEPTH} levels",
                                retryable=False,
                            )
                        if item_id not in visited:
                            visited.add(item_id)
                            if len(visited) > MAX_FOLDERS:
                                raise JobError(
                                    "too_many_folders",
                                    f"the folder tree has more than {MAX_FOLDERS} folders",
                                    retryable=False,
                                )
                            folders.append((item_id, depth + 1))
                        continue
                    file_entry = to_file_entry(entry)
                    # A file in several folders is listed once (the first place it was seen).
                    if file_entry is not None and item_id not in files:
                        files[item_id] = file_entry
                        if len(files) > MAX_FILES:
                            raise JobError(
                                "too_many_files",
                                f"the folder tree has more than {MAX_FILES} files",
                                retryable=False,
                            )
                keep_lease()
                next_token = page.get("nextPageToken")
                if not isinstance(next_token, str) or not next_token:
                    break
                page_token = next_token
        return list(files.values())


def to_file_entry(item: Mapping[str, object]) -> dict[str, object] | None:
    """A Drive file resource as a drive.sync v1 file entry; malformed items are skipped."""
    raw_name = item.get("name")
    raw_mime = item.get("mimeType")
    if not isinstance(raw_name, str) or not isinstance(raw_mime, str):
        return None
    # Names are untrusted data: drop invisible and reordering characters. A file whose name has
    # nothing readable left is kept, so it is never mistaken for a removed one.
    name = UNSAFE_NAME_CHARACTERS.sub("", raw_name).strip() or "(sem nome)"
    mime = UNSAFE_NAME_CHARACTERS.sub("", raw_mime).strip() or "application/octet-stream"
    revision = item.get("headRevisionId") or item.get("version") or item.get("modifiedTime")
    if not isinstance(revision, str) or not revision:
        return None
    entry: dict[str, object] = {
        "drive_file_id": item["id"],
        "name": name[:500],
        "mime_type": mime[:200],
        "revision": revision[:200],
    }
    size = item.get("size")
    if isinstance(size, str) and size.isdigit():
        entry["size_bytes"] = int(size)
    md5 = item.get("md5Checksum")
    if isinstance(md5, str) and MD5.match(md5):
        entry["md5_checksum"] = md5
    modified = item.get("modifiedTime")
    if isinstance(modified, str) and modified:
        entry["modified_at"] = modified
    return entry


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------
ClientFactory = Callable[[ServiceAccount], GoogleDriveClient]


def default_client_factory(timeout_seconds: float) -> ClientFactory:
    def build(account: ServiceAccount) -> GoogleDriveClient:
        return GoogleDriveClient(account, UrllibTransport(timeout_seconds=timeout_seconds))

    return build


def _context(context: JobContext) -> DriveSyncContext:
    sync = context.drive_sync_for_job()
    if sync is None:
        # Paused connections are not listed (and a lost lease fences this failure anyway).
        # Resuming the connection queues the job again.
        raise JobError(
            "drive_connection_paused",
            "the connection is paused or no longer leased to this worker",
            retryable=False,
        )
    return sync


def drive_sync_v1(credentials_dir: Path | None, client_factory: ClientFactory) -> Handler:
    def handle(context: JobContext, _payload: Mapping[str, object]) -> dict[str, object]:
        sync = _context(context)
        account = load_service_account(
            credentials_dir, context.job.workspace_id, sync.credential_ref
        )

        def keep_lease() -> None:
            if not context.extend_lease():
                raise JobError("lease_lost", "lease lost during the Drive sync", retryable=True)

        return {"files": client_factory(account).snapshot(sync.root_folder_id, keep_lease)}

    return handle
