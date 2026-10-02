"""The handler set a worker advertises, built from what is configured on this machine."""

from __future__ import annotations

from pathlib import Path

from jmos_worker.drive import ClientFactory, default_client_factory, drive_sync_v1
from jmos_worker.handlers import DEFAULT_HANDLERS, Handler, ai_model_check_v1
from jmos_worker.meetings import Transcriber, meeting_extract_v1, meeting_transcribe_v1
from jmos_worker.models import ModelAdapter


def build_handlers(
    adapter: ModelAdapter | None,
    *,
    transcriber: Transcriber | None = None,
    media_root: Path | None = None,
    drive_credentials_dir: Path | None = None,
    drive_client_factory: ClientFactory | None = None,
) -> dict[str, Handler]:
    """Model jobs need a model adapter; transcription needs a transcriber (and a media root).

    Drive sync is always advertised: without `JMOS_DRIVE_CREDENTIALS_DIR` the job fails with
    `drive_credentials_missing`, so the failure is visible instead of jobs waiting forever.
    """
    handlers = dict(DEFAULT_HANDLERS)
    handlers["drive.sync.v1"] = drive_sync_v1(
        drive_credentials_dir, drive_client_factory or default_client_factory(30.0)
    )
    if adapter is not None:
        handlers["ai.model_check.v1"] = ai_model_check_v1(adapter)
        handlers["meeting.extract.v1"] = meeting_extract_v1(adapter)
    if transcriber is not None:
        handlers["meeting.transcribe.v1"] = meeting_transcribe_v1(transcriber, media_root)
    return handlers
