import json
import logging
from datetime import UTC, datetime
from typing import Any

_ALLOWED_EXTRA_FIELDS = frozenset(
    {"duration_ms", "error_type", "event", "method", "request_id", "status_code"}
)


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for field in _ALLOWED_EXTRA_FIELDS:
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value
        return json.dumps(payload, separators=(",", ":"), sort_keys=True)


def configure_logging(level: str) -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)
    for logger_name in ("sarti", "sarti.database", "sarti.http"):
        logging.getLogger(logger_name).disabled = False
