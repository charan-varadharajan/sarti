"""Explicit Dart -> real HTTP -> PostgreSQL -> Dart contract host (BUG-011)."""

import asyncio
import base64
import json
import os
import shutil
import socket
import subprocess
import threading
import time
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

import pytest
import uvicorn
from httpx import ASGITransport, AsyncClient
from test_stage2_api import Api, StubWebAuthn

from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import memberships, permissions
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


@pytest.mark.skipif(
    os.environ.get("SARTI_RUN_MOBILE_CONTRACT") != "1",
    reason="Explicit opt-in: requires local Flutter SDK",
)
def test_real_http_postgresql_mobile_ciphertext_roundtrip() -> None:
    url = os.environ["SARTI_DATABASE_URL"]
    database = Database(url)
    app = create_app(Settings(environment="test", database_url=url), database, StubWebAuthn())

    async def prepare():
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            api = Api(client)
            first = await api.register(str(uuid4()))
            second = await api.register(str(uuid4()))
            response = await client.post("/v1/families", headers=api.headers(first), json={})
            assert response.status_code == 201
            family = response.json()
            with database.transaction() as c:
                c.execute(
                    memberships.insert().values(
                        family_id=UUID(family["id"]),
                        adult_id=UUID(second["adult_id"]),
                        role="guardian",
                        status="active",
                        created_at=datetime.now(UTC),
                    )
                )
                # Explicit prepared administrator permission; no UI prerequisite.

                calendar = next(r["id"] for r in family["resources"] if r["kind"] == "calendar")
                c.execute(
                    permissions.insert().values(
                        resource_id=UUID(calendar),
                        adult_id=UUID(second["adult_id"]),
                        permission="admin",
                    )
                )
            return {"familyId": family["id"], "calendarId": calendar, "devices": [first, second]}

    config = asyncio.run(prepare())
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen()
    config["baseUrl"] = f"http://127.0.0.1:{listener.getsockname()[1]}"
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
        encoded = base64.urlsafe_b64encode(json.dumps(config).encode()).decode()
        logs = root / "test-results"
        logs.mkdir(exist_ok=True)
        with (logs / "bug011-http-mobile.log").open("w") as log:
            result = subprocess.run(  # noqa: S603 - resolved installed Flutter executable
                [
                    flutter,
                    "test",
                    "test/postgres_sync_roundtrip_test.dart",
                    "--dart-define=SARTI_TEST_SYNC_CONFIG=" + encoded,
                    "--reporter",
                    "expanded",
                ],
                cwd=root / "mobile",
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=600,
            )
        assert result.returncode == 0, (
            "Mobile contract failed; see ignored test-results/bug011-http-mobile.log"
        )
    finally:
        server.should_exit = True
        thread.join(timeout=15)
        listener.close()
        database.close()
