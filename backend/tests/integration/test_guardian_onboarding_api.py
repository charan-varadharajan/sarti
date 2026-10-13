"""BUG-004: prepared households, device verification and initial relay boundaries."""

import asyncio
import base64
import hashlib
import os
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, update
from test_stage2_api import Api, StubWebAuthn, b64

from alembic import command
from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import invitations, memberships, resources
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


async def guardian_flow() -> None:
    url = os.environ["SARTI_DATABASE_URL"]
    db = Database(url)
    app = create_app(Settings(environment="test", database_url=url), db, StubWebAuthn())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        owner = await api.register(str(uuid4()))
        guardian = await api.register(str(uuid4()))
        outsider = await api.register(str(uuid4()))
        family = (await client.post("/v1/families", headers=api.headers(owner), json={})).json()
        other = (await client.post("/v1/families", headers=api.headers(outsider), json={})).json()
        fid = family["id"]
        path = f"/v1/families/{fid}/invitations"
        calendar = next(r["id"] for r in family["resources"] if r["kind"] == "calendar")
        profile = next(r["id"] for r in family["resources"] if r["kind"] == "family_profile")
        child = (
            await client.post(
                f"/v1/families/{fid}/resources",
                headers=api.headers(owner),
                json={"kind": "child_profile"},
            )
        ).json()["id"]
        nonce, ciphertext = os.urandom(24), os.urandom(64)

        def op(sequence, resource=calendar):
            return {
                "operation_id": str(uuid4()),
                "family_id": fid,
                "resource_id": resource,
                "protocol_version": 2,
                "device_sequence": sequence,
                "key_epoch": 1,
                "logical_version": {owner["device_id"]: sequence},
                "nonce": b64(nonce),
                "ciphertext": b64(ciphertext),
                "content_digest": b64(hashlib.sha256(nonce + ciphertext).digest()),
            }

        old = await client.post("/v1/sync/operations", headers=api.headers(owner), json=op(1))
        assert old.status_code == 201
        invite = (await client.post(path, headers=api.headers(owner))).json()
        assert len(invite["token"]) == 43
        assert (await client.get(path, headers=api.headers(outsider))).status_code == 404
        assert (
            await client.post(
                "/v1/invitations/accept",
                headers=api.headers(owner),
                json={"token": invite["token"]},
            )
        ).status_code == 404
        accepted = await client.post(
            "/v1/invitations/accept", headers=api.headers(guardian), json={"token": invite["token"]}
        )
        assert accepted.status_code == 200
        assert (
            await client.post(
                "/v1/invitations/accept",
                headers=api.headers(guardian),
                json={"token": invite["token"]},
            )
        ).status_code == 404
        assert (
            await client.get(f"/v1/families/{fid}/sync", headers=api.headers(guardian))
        ).status_code == 404
        pending = (await client.get("/v1/families", headers=api.headers(guardian))).json()[0]
        assert pending["status"] == "pending" and pending["resources"] == []
        review = (await client.get(path, headers=api.headers(owner))).json()[0]
        assert review["device_id"] == guardian["device_id"]
        assert "token" not in review and "token_digest" not in review
        digest = hashlib.sha256(
            base64.urlsafe_b64decode(review["signing_public_key"] + "==")
            + base64.urlsafe_b64decode(review["encryption_public_key"] + "==")
        ).hexdigest()
        payload = {
            "permissions": [
                {"resource_id": calendar, "permission": "read"},
                {"resource_id": profile, "permission": "read"},
            ],
            "expected_device_id": guardian["device_id"],
            "expected_key_digest": digest,
        }
        approval = f"{path}/{invite['id']}/approve"
        assert (
            await client.post(approval, headers=api.headers(outsider), json=payload)
        ).status_code == 404
        assert (
            await client.post(
                approval,
                headers=api.headers(owner),
                json=dict(payload, expected_device_id=str(uuid4())),
            )
        ).status_code == 409
        assert (
            await client.post(
                approval,
                headers=api.headers(owner),
                json=dict(payload, expected_key_digest="0" * 64),
            )
        ).status_code == 409
        wrong = dict(
            payload,
            permissions=[{"resource_id": other["resources"][0]["id"], "permission": "read"}],
        )
        assert (
            await client.post(approval, headers=api.headers(owner), json=wrong)
        ).status_code == 403
        duplicate = dict(payload, permissions=payload["permissions"] * 2)
        assert (
            await client.post(approval, headers=api.headers(owner), json=duplicate)
        ).status_code == 403
        assert (
            await client.post(approval, headers=api.headers(owner), json=payload)
        ).status_code == 200
        assert (
            await client.post(approval, headers=api.headers(owner), json=payload)
        ).status_code == 200
        expanded = dict(
            payload,
            permissions=payload["permissions"] + [{"resource_id": child, "permission": "read"}],
        )
        assert (
            await client.post(approval, headers=api.headers(owner), json=expanded)
        ).status_code == 409
        listed = (await client.get("/v1/families", headers=api.headers(guardian))).json()[0]
        assert {r["id"] for r in listed["resources"]} == {calendar, profile}
        assert {r["permission"] for r in listed["resources"]} == {"read"}
        assert listed["sync_start_cursor"] == old.json()["server_sequence"]
        first = (await client.get(f"/v1/families/{fid}/sync", headers=api.headers(guardian))).json()
        assert first["operations"] == [] and first["next_cursor"] >= listed["sync_start_cursor"]
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(owner), json=op(2, child))
        ).status_code == 201
        new = await client.post("/v1/sync/operations", headers=api.headers(owner), json=op(3))
        assert new.status_code == 201
        page = (await client.get(f"/v1/families/{fid}/sync", headers=api.headers(guardian))).json()
        assert [row["server_sequence"] for row in page["operations"]] == [
            new.json()["server_sequence"]
        ]
        assert (
            await client.get(
                f"/v1/families/{fid}/resources/{child}/devices", headers=api.headers(guardian)
            )
        ).status_code == 403
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(guardian), json=op(1))
        ).status_code == 403
        with pytest.raises(RuntimeError, match="guardian relay baseline"):
            command.downgrade(Config("alembic.ini"), "0006")
        with db.connect() as c:
            stored = c.execute(
                select(memberships.c.sync_start_cursor).where(
                    (memberships.c.family_id == UUID(fid))
                    & (memberships.c.adult_id == UUID(guardian["adult_id"]))
                )
            ).scalar_one()
            assert stored == listed["sync_start_cursor"]
        assert (
            await client.delete(f"{path}/{invite['id']}", headers=api.headers(owner))
        ).status_code == 409
        removed = await client.delete(
            f"/v1/families/{fid}/guardians/{guardian['adult_id']}", headers=api.headers(owner)
        )
        assert removed.status_code == 200
        assert (
            await client.get(f"/v1/families/{fid}/sync", headers=api.headers(guardian))
        ).status_code == 404
        with db.connect() as c:
            assert set(
                c.execute(
                    select(resources.c.key_epoch).where(resources.c.family_id == UUID(fid))
                ).scalars()
            ) == {2}
        # Explicit fresh invitation may re-enroll a removed guardian as pending.
        renewed = (await client.post(path, headers=api.headers(owner))).json()
        assert (
            await client.post(
                "/v1/invitations/accept",
                headers=api.headers(guardian),
                json={"token": renewed["token"]},
            )
        ).status_code == 200
        assert (
            await client.delete(f"{path}/{renewed['id']}", headers=api.headers(owner))
        ).status_code == 204
        assert (
            await client.post(
                f"{path}/{renewed['id']}/approve", headers=api.headers(owner), json=payload
            )
        ).status_code == 409
        expired = (await client.post(path, headers=api.headers(owner))).json()
        with db.transaction() as c:
            c.execute(
                update(invitations)
                .where(invitations.c.id == UUID(expired["id"]))
                .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
            )
        assert (
            await client.post(
                "/v1/invitations/accept",
                headers=api.headers(guardian),
                json={"token": expired["token"]},
            )
        ).status_code == 404
        invite2 = (await client.post(path, headers=api.headers(owner))).json()
        assert (
            await client.post(
                "/v1/invitations/accept",
                headers=api.headers(guardian),
                json={"token": invite2["token"]},
            )
        ).status_code == 200
        with db.transaction() as c:
            c.execute(
                update(invitations)
                .where(invitations.c.id == UUID(invite2["id"]))
                .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
            )
        assert (
            await client.post(
                f"{path}/{invite2['id']}/approve", headers=api.headers(owner), json=payload
            )
        ).status_code == 409
        fresh = (await client.post(path, headers=api.headers(owner))).json()
        assert (
            await client.post(
                "/v1/invitations/accept",
                headers=api.headers(guardian),
                json={"token": fresh["token"]},
            )
        ).status_code == 200
        assert (
            await client.delete(f"{path}/{invite2['id']}", headers=api.headers(owner))
        ).status_code == 204
        assert (await client.get("/v1/families", headers=api.headers(guardian))).json()[0][
            "status"
        ] == "pending"
        assert (
            await client.delete(f"{path}/{fresh['id']}", headers=api.headers(owner))
        ).status_code == 204
        for _ in range(5):
            assert (await client.post(path, headers=api.headers(owner))).status_code == 201
        assert (await client.post(path, headers=api.headers(owner))).status_code == 409
    db.close()


def test_guardian_approval_device_pin_permissions_baseline_and_abuse() -> None:
    asyncio.run(guardian_flow())
