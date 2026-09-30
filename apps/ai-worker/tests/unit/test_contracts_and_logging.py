from __future__ import annotations

import io
import json
import logging

import pytest

from jmos_worker.contracts import ContractRegistry
from jmos_worker.log import JsonFormatter
from jmos_worker.queue import JobError


def test_packaged_contracts_include_the_healthcheck() -> None:
    assert "system.healthcheck.v1" in ContractRegistry.load_packaged().contract_keys()


def test_healthcheck_output_is_strict() -> None:
    registry = ContractRegistry.load_packaged()
    valid = {
        "worker_id": "gpu-1",
        "worker_version": "0.1.0",
        "checked_at": "2026-09-30T12:00:00.123456+00:00",
    }
    registry.validate_output("system.healthcheck.v1", valid)
    with pytest.raises(JobError) as error:
        registry.validate_output("system.healthcheck.v1", {**valid, "extra": "x"})
    assert (error.value.code, error.value.retryable) == ("invalid_output", False)


def test_unknown_contract_is_a_permanent_error() -> None:
    with pytest.raises(JobError) as error:
        ContractRegistry.load_packaged().validate_input("nope.v1", {})
    assert (error.value.code, error.value.retryable) == ("unknown_job_type", False)


def test_json_logs_carry_correlation_fields_only() -> None:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger("test.json")
    logger.handlers[:] = [handler]
    logger.propagate = False
    logger.setLevel(logging.INFO)

    logger.info(
        "job leased",
        extra={"job_id": "j-1", "workspace_id": "w-1", "attempt": 2, "input": {"secret": "x"}},
    )

    entry = json.loads(stream.getvalue())
    assert entry["msg"] == "job leased"
    assert (entry["job_id"], entry["workspace_id"], entry["attempt"]) == ("j-1", "w-1", 2)
    assert "input" not in entry, "only allow-listed correlation fields are emitted"
