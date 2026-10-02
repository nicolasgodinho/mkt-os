from __future__ import annotations

import pytest

from jmos_worker.config import ConfigError, WorkerConfig

URL = "postgresql://jmos_worker:s3cret-value@127.0.0.1:54322/postgres"


def test_defaults_from_minimal_environment() -> None:
    config = WorkerConfig.from_env({"JMOS_WORKER_DATABASE_URL": URL, "JMOS_WORKER_ID": "gpu-1"})
    assert (config.worker_id, config.lease_seconds, config.log_level) == ("gpu-1", 300, "INFO")


def test_database_url_is_required() -> None:
    with pytest.raises(ConfigError, match="JMOS_WORKER_DATABASE_URL is required"):
        WorkerConfig.from_env({})


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        ({"JMOS_WORKER_DATABASE_URL": "mysql://x"}, "postgresql://"),
        ({"JMOS_WORKER_ID": "bad id!"}, "JMOS_WORKER_ID"),
        ({"JMOS_WORKER_LEASE_SECONDS": "5"}, "between 10 and 3600"),
        ({"JMOS_WORKER_LEASE_SECONDS": "abc"}, "must be an integer"),
        ({"JMOS_WORKER_LEASE_SECONDS": "20", "JMOS_WORKER_HEARTBEAT_SECONDS": "25"}, "shorter"),
        ({"JMOS_WORKER_LOG_LEVEL": "TRACE"}, "JMOS_WORKER_LOG_LEVEL"),
    ],
)
def test_invalid_values_are_rejected(overrides: dict[str, str], message: str) -> None:
    with pytest.raises(ConfigError, match=message):
        WorkerConfig.from_env({"JMOS_WORKER_DATABASE_URL": URL, **overrides})


def test_errors_and_redacted_url_never_contain_the_password() -> None:
    config = WorkerConfig.from_env({"JMOS_WORKER_DATABASE_URL": URL})
    assert "s3cret-value" not in config.redacted_database_url
    assert "jmos_worker:***@" in config.redacted_database_url
    with pytest.raises(ConfigError) as error:
        WorkerConfig.from_env({"JMOS_WORKER_DATABASE_URL": URL, "JMOS_WORKER_LEASE_SECONDS": "0"})
    assert "s3cret-value" not in str(error.value)
