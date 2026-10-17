"""BUG-026: own-device receipts after lost authority, no ciphertext disclosure."""

import asyncio
import hashlib
import os
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, update
from test_stage2_api import Api, StubWebAuthn, b64

from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import devices, sync_operations
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


async def scenario() -> None:
    db = Database(os.environ["SARTI_DATABASE_URL"])
    app = create_app(Settings(database_url=os.environ["SARTI_DATABASE_URL"]), db, StubWebAuthn())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        owner = await api.register(str(uuid4()))
        peer = await api.register(str(uuid4()))
        h, p = api.headers(owner), api.headers(peer)
        a = (await client.post("/v1/families", headers=h)).json()
        b = (await client.post("/v1/families", headers=p)).json()
        ca = next(r for r in a["resources"] if r["kind"] == "calendar")
        cb = next(r for r in b["resources"] if r["kind"] == "calendar")
        invitation = (await client.post(f"/v1/families/{a['id']}/invitations", headers=h)).json()
        assert (
            await client.post(
                "/v1/invitations/accept", headers=p, json={"token": invitation["token"]}
            )
        ).status_code == 200
        assert (
            await client.post(
                f"/v1/families/{a['id']}/invitations/{invitation['id']}/approve",
                headers=h,
                json={"permissions": [{"resource_id": ca["id"], "permission": "write"}]},
            )
        ).status_code == 200

        def operation(family: dict, resource: dict, sequence: int) -> dict:
            nonce, ciphertext = os.urandom(24), os.urandom(48)
            return {
                "protocol_version": 2,
                "operation_id": str(uuid4()),
                "family_id": family["id"],
                "resource_id": resource["id"],
                "device_sequence": sequence,
                "key_epoch": resource["key_epoch"],
                "logical_version": {peer["device_id"]: sequence},
                "nonce": b64(nonce),
                "ciphertext": b64(ciphertext),
                "content_digest": b64(hashlib.sha256(nonce + ciphertext).digest()),
            }

        original = operation(a, ca, 1)
        review = {
            k: original[k]
            for k in (
                "operation_id",
                "family_id",
                "resource_id",
                "device_sequence",
                "content_digest",
            )
        }
        route = "/v1/sync/sequence-review"
        assert (await client.post(route, json=review)).status_code == 401
        # Still authorized: do not skip or quarantine an ordinary interrupted retry.
        assert (await client.post(route, headers=p, json=review)).status_code == 409
        assert (
            await client.post("/v1/sync/operations", headers=p, json=original)
        ).status_code == 201
        assert (
            await client.delete(f"/v1/families/{a['id']}/guardians/{peer['adult_id']}", headers=h)
        ).status_code == 200
        assert (
            await client.post("/v1/sync/operations", headers=p, json=original)
        ).status_code == 404
        response = await client.post(route, headers=p, json=review)
        assert response.status_code == 200, response.text
        assert response.headers["Cache-Control"] == "no-store"
        assert response.json() == {
            "operation_id": original["operation_id"],
            "device_id": peer["device_id"],
            "last_device_sequence": 1,
            "receipt": "accepted",
        }
        assert set(response.json()) == {
            "operation_id",
            "device_id",
            "last_device_sequence",
            "receipt",
        }
        assert (await client.get(f"/v1/families/{a['id']}/sync", headers=p)).status_code == 404
        assert (
            await client.post(route, headers=p, json={**review, "content_digest": b64(b"x" * 32)})
        ).status_code == 409
        assert (
            await client.post(route, headers=p, json={**review, "family_id": b["id"]})
        ).status_code == 409
        assert (
            await client.post(route, headers=p, json={**review, "device_sequence": 2})
        ).status_code == 409
        assert (
            await client.post(route, headers=p, json={**review, "plaintext": "synthetic canary"})
        ).status_code == 422
        # The other account cannot see an accepted receipt from this device.
        forged = {**review, "family_id": str(uuid4())}
        foreign = await client.post(route, headers=h, json=forged)
        assert foreign.status_code == 200
        assert foreign.json()["receipt"] == "not_accepted"
        assert foreign.json()["last_device_sequence"] == 0
        assert foreign.json()["device_id"] == owner["device_id"]
        # Read-only review never mutates/reserves either sequence.
        with db.connect() as c:
            assert (
                c.execute(
                    select(devices.c.last_sync_sequence).where(
                        devices.c.id == UUID(peer["device_id"])
                    )
                ).scalar_one()
                == 1
            )
        next_upload = operation(b, cb, 2)
        assert (
            await client.post("/v1/sync/operations", headers=p, json=next_upload)
        ).status_code == 201
        with db.transaction() as c:
            c.execute(
                update(sync_operations)
                .where(sync_operations.c.operation_id == UUID(original["operation_id"]))
                .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
            )
        expired = await client.post(route, headers=p, json=review)
        assert expired.json()["receipt"] == "unknown"
        assert expired.json()["last_device_sequence"] == 2
        never_sent = operation(a, ca, 3)
        unseen = await client.post(route, headers=p, json={k: never_sent[k] for k in review})
        assert unseen.json()["receipt"] == "not_accepted"
        assert unseen.json()["last_device_sequence"] == 2
        assert (
            await client.post("/v1/sync/operations", headers=p, json=operation(b, cb, 4))
        ).status_code == 409
        assert (
            await client.post("/v1/sync/operations", headers=p, json=operation(b, cb, 3))
        ).status_code == 201
        with db.transaction() as c:
            c.execute(
                update(devices)
                .where(devices.c.id == UUID(peer["device_id"]))
                .values(state="revoked")
            )
        assert (await client.post(route, headers=p, json=review)).status_code == 401
    db.close()


def test_lost_authority_sequence_receipt_and_other_household() -> None:
    asyncio.run(scenario())
