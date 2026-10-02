"""Worker configuration, read from the environment only (never from files in the repo)."""

from __future__ import annotations

import os
import re
import socket
from collections.abc import Mapping
from dataclasses import dataclass, field
from urllib.parse import urlsplit

# Mirrors worker.assert_worker_id in supabase/migrations (the database is the enforcement point;
# this only turns a bad value into a clear configuration error at startup).
WORKER_ID_PATTERN = re.compile(r"^[A-Za-z0-9._:-]{1,100}$")
LOG_LEVELS = frozenset({"DEBUG", "INFO", "WARNING", "ERROR"})
# The model runtime is local-only (docs/08 §2): the worker never reaches it over the network, and
# the runtime itself must never be exposed to the internet.
LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})
DEFAULT_OLLAMA_URL = "http://127.0.0.1:11434"
# Task profile -> default local model (docs/08 §3). Overridable per profile through the environment.
DEFAULT_MODEL_PROFILES: Mapping[str, str] = {"reasoning": "gpt-oss:20b"}


class ConfigError(ValueError):
    """Invalid or missing configuration. Messages never include secret values."""


@dataclass(frozen=True, slots=True)
class WorkerConfig:
    database_url: str
    worker_id: str
    poll_interval_seconds: float = 2.0
    lease_seconds: int = 300
    heartbeat_interval_seconds: float = 15.0
    log_level: str = "INFO"
    ollama_url: str = DEFAULT_OLLAMA_URL
    model_profiles: Mapping[str, str] = field(default_factory=lambda: dict(DEFAULT_MODEL_PROFILES))
    model_timeout_seconds: float = 120.0

    @classmethod
    def from_env(cls, env: Mapping[str, str] = os.environ) -> WorkerConfig:
        database_url = env.get("JMOS_WORKER_DATABASE_URL", "").strip()
        if not database_url:
            raise ConfigError("JMOS_WORKER_DATABASE_URL is required")
        if not database_url.startswith(("postgresql://", "postgres://")):
            raise ConfigError("JMOS_WORKER_DATABASE_URL must be a postgresql:// URL")

        worker_id = env.get("JMOS_WORKER_ID", "").strip() or default_worker_id()
        if not WORKER_ID_PATTERN.match(worker_id):
            raise ConfigError("JMOS_WORKER_ID must match [A-Za-z0-9._:-]{1,100}")

        log_level = env.get("JMOS_WORKER_LOG_LEVEL", "INFO").strip().upper()
        if log_level not in LOG_LEVELS:
            raise ConfigError(f"JMOS_WORKER_LOG_LEVEL must be one of {sorted(LOG_LEVELS)}")

        lease_seconds = _int(env, "JMOS_WORKER_LEASE_SECONDS", 300, low=10, high=3600)
        heartbeat = _float(env, "JMOS_WORKER_HEARTBEAT_SECONDS", 15.0, low=1.0, high=300.0)
        if heartbeat >= lease_seconds:
            raise ConfigError(
                "JMOS_WORKER_HEARTBEAT_SECONDS must be shorter than JMOS_WORKER_LEASE_SECONDS"
            )

        ollama_url = env.get("JMOS_OLLAMA_URL", "").strip() or DEFAULT_OLLAMA_URL
        parts = urlsplit(ollama_url)
        if parts.scheme not in ("http", "https") or parts.hostname not in LOOPBACK_HOSTS:
            raise ConfigError(
                "JMOS_OLLAMA_URL must be an http(s) URL on a loopback address "
                "(localhost, 127.0.0.1 or ::1)"
            )
        model_profiles = {
            profile: env.get(f"JMOS_MODEL_{profile.upper()}", "").strip() or default
            for profile, default in DEFAULT_MODEL_PROFILES.items()
        }
        model_timeout = _float(env, "JMOS_MODEL_TIMEOUT_SECONDS", 120.0, low=1.0, high=1800.0)
        if model_timeout >= lease_seconds:
            raise ConfigError(
                "JMOS_MODEL_TIMEOUT_SECONDS must be shorter than JMOS_WORKER_LEASE_SECONDS"
            )

        return cls(
            database_url=database_url,
            worker_id=worker_id,
            poll_interval_seconds=_float(env, "JMOS_WORKER_POLL_SECONDS", 2.0, low=0.05, high=60.0),
            lease_seconds=lease_seconds,
            heartbeat_interval_seconds=heartbeat,
            log_level=log_level,
            ollama_url=ollama_url,
            model_profiles=model_profiles,
            model_timeout_seconds=model_timeout,
        )

    @property
    def redacted_database_url(self) -> str:
        return redact_url(self.database_url)


def default_worker_id() -> str:
    host = re.sub(r"[^A-Za-z0-9._-]", "-", socket.gethostname())[:80] or "worker"
    return f"{host}-{os.getpid()}"


def redact_url(url: str) -> str:
    return re.sub(r"//([^:/@]+):[^@]*@", r"//\1:***@", url)


def _int(env: Mapping[str, str], name: str, default: int, *, low: int, high: int) -> int:
    raw = env.get(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        value = int(raw)
    except ValueError as error:
        raise ConfigError(f"{name} must be an integer") from error
    if not low <= value <= high:
        raise ConfigError(f"{name} must be between {low} and {high}")
    return value


def _float(env: Mapping[str, str], name: str, default: float, *, low: float, high: float) -> float:
    raw = env.get(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        value = float(raw)
    except ValueError as error:
        raise ConfigError(f"{name} must be a number") from error
    if not low <= value <= high:
        raise ConfigError(f"{name} must be between {low} and {high}")
    return value
