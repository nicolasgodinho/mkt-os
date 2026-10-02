"""Command line entry point.

python -m jmos_worker run     start the worker loop (Ctrl+C / SIGTERM for graceful shutdown)
python -m jmos_worker check   verify configuration, connectivity, role privileges and contracts
"""

from __future__ import annotations

import argparse
import json
import logging
import signal
import sys
from types import FrameType

import psycopg

from jmos_worker import __version__
from jmos_worker.config import ConfigError, WorkerConfig
from jmos_worker.contracts import ContractRegistry
from jmos_worker.handlers import build_handlers
from jmos_worker.log import configure_logging
from jmos_worker.models import OllamaAdapter
from jmos_worker.queue import PostgresJobQueue, WorkerRoleError
from jmos_worker.runner import Worker

logger = logging.getLogger("jmos_worker")


def build_worker(config: WorkerConfig) -> tuple[Worker, PostgresJobQueue]:
    queue = PostgresJobQueue(
        config.database_url,
        worker_id=config.worker_id,
        version=__version__,
        lease_seconds=config.lease_seconds,
    )
    worker = Worker(
        worker_id=config.worker_id,
        queue=queue,
        handlers=build_handlers(
            OllamaAdapter(
                config.ollama_url,
                config.model_profiles,
                timeout_seconds=config.model_timeout_seconds,
            )
        ),
        contracts=ContractRegistry.load_packaged(),
        poll_interval_seconds=config.poll_interval_seconds,
        heartbeat_interval_seconds=config.heartbeat_interval_seconds,
    )
    return worker, queue


def install_signal_handlers(worker: Worker) -> None:
    def handle(signum: int, _frame: FrameType | None) -> None:
        if worker.stopping:
            # Second signal: exit now. The in-flight job's lease expires and it is redelivered.
            raise SystemExit(128 + signum)
        logger.info("shutdown requested (signal %s); finishing the current job", signum)
        worker.request_stop()

    signal.signal(signal.SIGINT, handle)
    signal.signal(signal.SIGTERM, handle)
    if hasattr(signal, "SIGBREAK"):  # Windows console Ctrl+Break
        signal.signal(signal.SIGBREAK, handle)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="jmos-worker", description=__doc__)
    parser.add_argument("command", choices=["run", "check"])
    args = parser.parse_args(argv)

    try:
        config = WorkerConfig.from_env()
    except ConfigError as error:
        print(f"configuration error: {error}", file=sys.stderr)
        return 2
    configure_logging(config.log_level)

    worker, queue = build_worker(config)
    try:
        queue.assert_worker_role()
    except WorkerRoleError as error:
        logger.error("%s", error, extra={"worker_id": config.worker_id})
        queue.close()
        return 3
    except psycopg.OperationalError:
        logger.exception(
            "cannot connect to %s",
            config.redacted_database_url,
            extra={"worker_id": config.worker_id},
        )
        queue.close()
        return 4

    if args.command == "check":
        queue.close()
        print(
            json.dumps(
                {
                    "status": "ok",
                    "worker_id": config.worker_id,
                    "version": __version__,
                    "database": config.redacted_database_url,
                    "job_types": worker.job_types,
                }
            )
        )
        return 0

    install_signal_handlers(worker)
    worker.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
