"""Structured JSON-lines logging (docs/09 "Observability baseline").

Correlation fields (trace_id, workspace_id, client_id, job_id, ...) are passed with
`extra=` and emitted as top-level keys. Job payloads and secrets are never logged.
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime
from typing import TextIO

CONTEXT_FIELDS = (
    "worker_id",
    "trace_id",
    "workspace_id",
    "client_id",
    "job_id",
    "job_type",
    "attempt",
    "outcome",
    "error_code",
    "duration_ms",
)


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry: dict[str, object] = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname.lower(),
            "logger": record.name,
            "msg": record.getMessage(),
        }
        for field in CONTEXT_FIELDS:
            value = record.__dict__.get(field)
            if value is not None:
                entry[field] = str(value) if not isinstance(value, int | float) else value
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, ensure_ascii=False)


def configure_logging(level: str, stream: TextIO = sys.stdout) -> None:
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)
