"""Job payload contracts, generated from packages/core by `pnpm contracts:generate`.

The worker never trusts payloads: inputs are validated before a handler runs, and outputs
are validated before they are written back (docs/05 §3, docs/08 §7).
"""

from __future__ import annotations

import json
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from importlib import resources
from typing import cast

from jsonschema import Draft202012Validator

from jmos_worker.queue import JobError

ContractDocument = Mapping[str, object]


@dataclass(frozen=True, slots=True)
class JobContract:
    key: str
    input: Draft202012Validator
    output: Draft202012Validator


def packaged_documents() -> list[ContractDocument]:
    """The generated contract documents shipped inside the package (`contract_schemas/`)."""
    documents: list[ContractDocument] = []
    for entry in (resources.files("jmos_worker") / "contract_schemas").iterdir():
        if entry.name.endswith(".json"):
            documents.append(cast(dict[str, object], json.loads(entry.read_text(encoding="utf-8"))))
    return documents


class ContractRegistry:
    def __init__(self, contracts: Mapping[str, JobContract]) -> None:
        self._contracts = dict(contracts)

    @classmethod
    def from_documents(cls, documents: Iterable[ContractDocument]) -> ContractRegistry:
        contracts: dict[str, JobContract] = {}
        for document in documents:
            key = f"{document['type']}.v{document['schema_version']}"
            if key in contracts:
                raise ValueError(f"duplicate job contract {key}")
            input_schema = cast(dict[str, object], document["input"])
            output_schema = cast(dict[str, object], document["output"])
            Draft202012Validator.check_schema(input_schema)
            Draft202012Validator.check_schema(output_schema)
            contracts[key] = JobContract(
                key=key,
                input=Draft202012Validator(input_schema),
                output=Draft202012Validator(output_schema),
            )
        return cls(contracts)

    @classmethod
    def load_packaged(cls) -> ContractRegistry:
        return cls.from_documents(packaged_documents())

    def contract_keys(self) -> frozenset[str]:
        return frozenset(self._contracts)

    def validate_input(self, key: str, payload: object) -> None:
        self._validate(key, "input", payload, code="invalid_input")

    def validate_output(self, key: str, payload: object) -> None:
        self._validate(key, "output", payload, code="invalid_output")

    def _validate(self, key: str, direction: str, payload: object, *, code: str) -> None:
        contract = self._contracts.get(key)
        if contract is None:
            raise JobError("unknown_job_type", f"no contract for {key}", retryable=False)
        validator = contract.input if direction == "input" else contract.output
        error = next(iter(validator.iter_errors(payload)), None)
        if error is not None:
            location = "/".join(str(part) for part in error.absolute_path) or "(root)"
            # Report the failing schema rule and location, never the payload values themselves.
            raise JobError(
                code,
                f"{direction} violates {key} at {location}: {error.validator} constraint",
                retryable=False,
            )
