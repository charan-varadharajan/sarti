import json
import logging

from sarti_backend.core.logging import JsonFormatter


def test_json_logging_uses_only_allowlisted_context() -> None:
    record = logging.LogRecord("sarti", logging.INFO, "", 0, "complete", (), None)
    record.request_id = "request-1"
    record.secret = "must-not-appear"

    payload = json.loads(JsonFormatter().format(record))

    assert payload["request_id"] == "request-1"
    assert "secret" not in payload
    assert "must-not-appear" not in json.dumps(payload)
