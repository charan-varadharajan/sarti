"""CLOUD-API/QUOTA/MIG-001: real PostgreSQL authorization and atomic replica budget."""

import asyncio
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import create_engine, select, text, update
from test_stage2_api import Api, StubWebAuthn

from sarti_backend.ai.broker import reserve_attempt
from sarti_backend.core.config import Settings
from sarti_backend.core.errors import ApiError
from sarti_backend.db.database import Database
from sarti_backend.db.schema import ai_usage, devices
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


def test_atomic_budget_across_connections_and_expiry() -> None:
    engine = create_engine(os.environ["SARTI_DATABASE_URL"])
    now = datetime.now(UTC)
    adult = uuid4()
    with engine.begin() as c:
        c.execute(ai_usage.delete())

    def attempt(_: int) -> bool:
        try:
            with engine.begin() as c:
                reserve_attempt(c, adult, now)
            return True
        except ApiError:
            return False

    with ThreadPoolExecutor(max_workers=8) as pool:
        outcomes = list(pool.map(attempt, range(20)))
    assert sum(outcomes) == 10
    with engine.begin() as c:
        assert (
            c.execute(select(ai_usage.c.attempts).where(ai_usage.c.scope == "global")).scalar_one()
            == 10
        )
        c.execute(update(ai_usage).where(ai_usage.c.scope == "global").values(attempts=1000))
    with pytest.raises(ApiError), engine.begin() as c:
        reserve_attempt(c, uuid4(), now)
    with engine.begin() as c:
        c.execute(update(ai_usage).values(expires_at=now - timedelta(seconds=1)))
        reserve_attempt(c, adult, now)
        assert (
            c.execute(
                select(ai_usage.c.attempts).where(ai_usage.c.scope == str(adult))
            ).scalar_one()
            == 1
        )
        c.execute(ai_usage.delete())
    engine.dispose()


def test_api_authorization_disabled_consent_and_account_purge(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls = []

    async def fake(tokens: list[str], **kwargs: object) -> dict[str, int]:
        calls.append(tokens)
        return {"timeHour": 12, "timeMinute": 0}

    monkeypatch.setattr("sarti_backend.api.ai.generate_proposal", fake)

    async def flow() -> None:
        database = Database(os.environ["SARTI_DATABASE_URL"])
        settings = Settings(environment="test", database_url=os.environ["SARTI_DATABASE_URL"])
        app = create_app(settings, database, StubWebAuthn())
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            api = Api(client)
            adult = await api.register(str(uuid4()))
            headers = api.headers(adult)
            body = {"version": 1, "consent_version": 3, "tokens": ["noon"]}
            assert (await client.post("/v1/ai/proposals", json=body)).status_code == 401
            capability = await client.get("/v1/ai/capability", headers=headers)
            assert capability.json()["available"] is False
            assert capability.headers["Cache-Control"] == "no-store"
            assert (
                await client.post("/v1/ai/proposals", headers=headers, json=body)
            ).status_code == 503
            assert calls == []
            settings.cloud_ai_enabled = True
            settings.cloud_ai_reviewed = True
            settings.cloud_ai_model = "gemini-2.5-flash-lite"
            settings.gemini_api_key = "synthetic"
            for bad in [{"consent_version": 2}, {"tokens": ["private name"]}, {"raw": "private"}]:
                response = await client.post(
                    "/v1/ai/proposals", headers=headers, json={**body, **bad}
                )
                assert response.status_code == 422
                assert "private" not in response.text
            response = await client.post("/v1/ai/proposals", headers=headers, json=body)
            assert response.status_code == 200 and response.json()["timeHour"] == 12
            assert response.headers["Cache-Control"] == "no-store" and calls == [["noon"]]
            with database.transaction() as c:
                c.execute(
                    update(devices)
                    .where(devices.c.id == UUID(adult["device_id"]))
                    .values(state="revoked")
                )
            assert (
                await client.post("/v1/ai/proposals", headers=headers, json=body)
            ).status_code == 401
            assert len(calls) == 1
            with database.transaction() as c:
                c.execute(text("DELETE FROM adults WHERE id=:id"), {"id": UUID(adult["adult_id"])})
                assert (
                    c.execute(select(ai_usage).where(ai_usage.c.scope == adult["adult_id"])).first()
                    is None
                )
                c.execute(ai_usage.delete())
        database.close()

    asyncio.run(flow())
