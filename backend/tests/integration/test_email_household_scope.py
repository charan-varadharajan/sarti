"""S5-EMAIL-002: real PostgreSQL and sealed boxes; no provider is contacted."""

import asyncio
import base64
import hashlib
import json
import os
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from nacl.public import PrivateKey, SealedBox
from sqlalchemy import delete, select, update
from test_stage2_api import Api, StubWebAuthn

from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import (
    devices,
    email_suggestion_deliveries,
    families,
    memberships,
    permissions,
)
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


async def scenario() -> None:
    db = Database(os.environ["SARTI_DATABASE_URL"])
    # Synthetic local worker authentication only; never a deployment credential.
    secret = "synthetic-stage5-worker-fixture"  # noqa: S105
    app = create_app(
        Settings(database_url=os.environ["SARTI_DATABASE_URL"], email_worker_secret=secret),
        db,
        StubWebAuthn(),
    )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        owner = await api.register(str(uuid4()))
        caregiver = await api.register(str(uuid4()))
        outsider = await api.register(str(uuid4()))
        key = PrivateKey.generate()
        h = api.headers(owner)
        a = (await client.post("/v1/families", headers=h)).json()
        b = (await client.post("/v1/families", headers=h)).json()
        tokens = {f["id"]: str(uuid4()) for f in [a, b]}
        now = datetime.now(UTC)
        with db.transaction() as c:
            c.execute(
                update(devices)
                .where(devices.c.id == UUID(owner["device_id"]))
                .values(encryption_public_key=bytes(key.public_key))
            )
            for family_id, token in tokens.items():
                c.execute(
                    update(families)
                    .where(families.c.id == UUID(family_id))
                    .values(email_token_digest=hashlib.sha256(token.encode()).digest())
                )
            c.execute(
                memberships.insert().values(
                    family_id=UUID(a["id"]),
                    adult_id=UUID(caregiver["adult_id"]),
                    role="limited_caregiver",
                    status="active",
                    created_at=now,
                    expires_at=now + timedelta(hours=1),
                )
            )
        suggestions = []
        for family in [a, b]:
            response = await client.post(
                "/v1/email/ingest",
                headers={"X-Worker-Secret": secret},
                json={
                    "family_token": tokens[family["id"]],
                    "sender": "synthetic@example.invalid",
                    "subject": "Synthetic scoped email",
                    "body": "Review this on-device only.",
                },
            )
            assert response.status_code == 201, response.text
            suggestions.append(response.json()["suggestion_id"])
        with db.connect() as c:
            addressed = c.execute(select(email_suggestion_deliveries)).mappings().all()
            own = [r for r in addressed if str(r["suggestion_id"]) in suggestions]
            assert len(own) == 2
            assert all(r["device_id"] == UUID(owner["device_id"]) for r in own)
            for row in own:
                decrypted = json.loads(SealedBox(key).decrypt(row["ciphertext"]))
                assert decrypted["version"] == 2
                assert decrypted["family_id"] in tokens
                assert decrypted["suggestion_id"] == str(row["suggestion_id"])
        response = await client.get("/v1/email/suggestions", headers=h)
        assert response.status_code == 200, response.text
        assert response.headers["Cache-Control"] == "no-store"
        assert {r["family_id"] for r in response.json()} == set(tokens)
        for row in response.json():
            decoded = json.loads(
                SealedBox(key).decrypt(
                    base64.urlsafe_b64decode(
                        row["ciphertext"] + "=" * (-len(row["ciphertext"]) % 4)
                    )
                )
            )
            assert decoded["family_id"] == row["family_id"]
            assert "sender" not in row and "subject" not in row and "body" not in row
        assert (
            await client.get("/v1/email/suggestions", headers=api.headers(caregiver))
        ).json() == []
        assert (
            await client.get("/v1/email/suggestions", headers=api.headers(outsider))
        ).json() == []
        # A stale addressed delivery cannot bypass a narrowed resource grant.
        calendar = next(r for r in a["resources"] if r["kind"] == "calendar")
        with db.transaction() as c:
            c.execute(
                delete(permissions).where(
                    permissions.c.adult_id == UUID(owner["adult_id"]),
                    permissions.c.resource_id == UUID(calendar["id"]),
                )
            )
        remaining = await client.get("/v1/email/suggestions", headers=h)
        assert {r["family_id"] for r in remaining.json()} == {b["id"]}
        with db.transaction() as c:
            c.execute(
                update(devices)
                .where(devices.c.id == UUID(owner["device_id"]))
                .values(state="revoked")
            )
        assert (await client.get("/v1/email/suggestions", headers=h)).status_code == 401
    db.close()


def test_email_household_binding_and_limited_recipient_isolation() -> None:
    asyncio.run(scenario())
