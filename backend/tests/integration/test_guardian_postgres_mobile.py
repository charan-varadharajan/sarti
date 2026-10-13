"""Opt-in two-installation Dart/HTTP/PostgreSQL guardian protocol host."""

import os
import shutil
import socket
import subprocess
import threading
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

import pytest
import uvicorn
from fastapi import Response
from pydantic import BaseModel
from sqlalchemy import update
from test_stage2_api import StubWebAuthn

from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import sync_operations
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


class FixtureFamily(BaseModel):
    family_id: UUID


@pytest.mark.skipif(
    os.environ.get("SARTI_RUN_GUARDIAN_CONTRACT") != "1",
    reason="Explicit opt-in: local Flutter SDK required",
)
def test_guardian_real_http_postgresql_dart_handoff() -> None:
    url = os.environ["SARTI_DATABASE_URL"]
    database = Database(url)
    app = create_app(Settings(environment="test", database_url=url), database, StubWebAuthn())

    # This synthetic-only fixture route never exists in the shipping app.
    @app.post("/__fixture__/expire", status_code=204)
    def expire(payload: FixtureFamily) -> Response:
        with database.transaction() as connection:
            connection.execute(
                update(sync_operations)
                .where(sync_operations.c.family_id == payload.family_id)
                .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
            )
        return Response(status_code=204)

    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen()
    base = f"http://127.0.0.1:{listener.getsockname()[1]}"
    server = uvicorn.Server(uvicorn.Config(app, log_level="critical", access_log=False))
    thread = threading.Thread(target=server.run, kwargs={"sockets": [listener]}, daemon=True)
    thread.start()
    root = Path(__file__).resolve().parents[3]
    try:
        deadline = time.monotonic() + 15
        while not server.started and thread.is_alive() and time.monotonic() < deadline:
            time.sleep(0.05)
        assert server.started
        flutter = shutil.which("flutter")
        assert flutter is not None
        logs = root / "test-results"
        logs.mkdir(exist_ok=True)
        with (logs / "bug004-http-mobile.log").open("w") as log:
            result = subprocess.run(  # noqa: S603 - installed Flutter executable
                [
                    flutter,
                    "test",
                    "test/guardian_postgres_roundtrip_test.dart",
                    "--dart-define=SARTI_GUARDIAN_TEST_URL=" + base,
                    "--reporter",
                    "expanded",
                ],
                cwd=root / "mobile",
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=600,
            )
        assert result.returncode == 0, (
            "Guardian contract failed; see ignored test-results/bug004-http-mobile.log"
        )
    finally:
        server.should_exit = True
        thread.join(timeout=15)
        listener.close()
        database.close()
