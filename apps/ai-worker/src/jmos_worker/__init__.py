"""Jansen Marketing OS local AI Worker.

Consumes the durable job queue in Postgres over an outbound connection (docs/08 §2).
It never listens on a network port and never receives inbound traffic.
"""

__version__ = "0.1.0"
