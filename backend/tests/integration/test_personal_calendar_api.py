"""ADR-038 private-resource and private-backup authorization boundaries."""

import asyncio
import hashlib
import os
from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from httpx import ASGITransport, AsyncClient
from sqlalchemy import create_engine, select, update
from test_stage2_api import Api, StubWebAuthn, b64

from sarti_backend.api.sync import _grant_message
from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import devices, families, memberships, personal_backups, resources
from sarti_backend.households.device_replacement import advance_replacement_epochs
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


async def flow() -> None:
    url = os.environ["SARTI_DATABASE_URL"]
    database = Database(url)
    engine = create_engine(url)
    app = create_app(Settings(environment="test", database_url=url), database, StubWebAuthn())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        signing = Ed25519PrivateKey.generate()
        owner = await api.register(str(uuid4()))
        adult = await api.register(str(uuid4()), signing.public_key().public_bytes_raw())
        stranger = await api.register(str(uuid4()))
        family = (await client.post("/v1/families", headers=api.headers(owner), json={})).json()
        fid = family["id"]
        with engine.begin() as connection:
            connection.execute(
                memberships.insert().values(
                    family_id=UUID(fid),
                    adult_id=UUID(adult["adult_id"]),
                    role="guardian",
                    status="active",
                    created_at=datetime.now(UTC),
                )
            )
        path = f"/v1/families/{fid}/resources"
        rid = str(uuid4())
        body = {"kind": "personal_calendar", "resource_id": rid}
        assert (
            await client.post(
                path,
                headers=api.headers(adult),
                json={**body, "share_with_calendar_guardians": True},
            )
        ).status_code == 403
        assert (await client.post(path, headers=api.headers(adult), json=body)).status_code == 201
        assert (await client.post(path, headers=api.headers(adult), json=body)).status_code == 201
        assert (await client.post(path, headers=api.headers(owner), json=body)).status_code == 409
        assert (
            await client.post(path, headers=api.headers(stranger), json=body)
        ).status_code == 404
        listing = (await client.get("/v1/families", headers=api.headers(owner))).json()
        assert all(r["id"] != rid for f in listing for r in f["resources"])
        own = (await client.get("/v1/families", headers=api.headers(adult))).json()
        assert any(
            r["id"] == rid and r["permission"] == "admin" for f in own for r in f["resources"]
        )
        directory = f"{path}/{rid}/devices"
        assert (await client.get(directory, headers=api.headers(owner))).status_code == 403
        assert (await client.get(directory, headers=api.headers(stranger))).status_code == 404
        peers = (await client.get(directory, headers=api.headers(adult))).json()
        assert [p["device_id"] for p in peers] == [adult["device_id"]]
        wrapped = b"w" * 80

        def grant(recipient: str) -> dict[str, object]:
            signature = signing.sign(
                _grant_message(UUID(rid), 1, UUID(recipient), UUID(adult["device_id"]), wrapped)
            )
            return {
                "family_id": fid,
                "resource_id": rid,
                "key_epoch": 1,
                "recipient_device_id": recipient,
                "wrapped_key": b64(wrapped),
                "signature": b64(signature),
            }

        assert (
            await client.post(
                "/v1/key-grants", headers=api.headers(adult), json=grant(owner["device_id"])
            )
        ).status_code == 403
        assert (
            await client.post(
                "/v1/key-grants", headers=api.headers(adult), json=grant(adult["device_id"])
            )
        ).status_code == 201
        assert (await client.get("/v1/key-grants", headers=api.headers(owner))).json() == []
        nonce = os.urandom(24)
        ciphertext = os.urandom(48)
        operation = {
            "protocol_version": 2,
            "operation_id": str(uuid4()),
            "family_id": fid,
            "resource_id": rid,
            "device_sequence": 1,
            "key_epoch": 1,
            "logical_version": {adult["device_id"]: 1},
            "nonce": b64(nonce),
            "ciphertext": b64(ciphertext),
            "content_digest": b64(hashlib.sha256(nonce + ciphertext).digest()),
        }
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(owner), json=operation)
        ).status_code == 403
        uploaded = await client.post(
            "/v1/sync/operations", headers=api.headers(adult), json=operation
        )
        assert uploaded.status_code == 201, uploaded.text
        duplicate = await client.post(
            "/v1/sync/operations", headers=api.headers(adult), json=operation
        )
        assert duplicate.status_code == 201 and duplicate.json()["duplicate"]
        assert (
            await client.post(
                "/v1/sync/operations",
                headers=api.headers(adult),
                json={**operation, "operation_id": str(uuid4())},
            )
        ).status_code == 409
        assert (await client.get(f"/v1/families/{fid}/sync", headers=api.headers(owner))).json()[
            "operations"
        ] == []
        assert (
            len(
                (await client.get(f"/v1/families/{fid}/sync", headers=api.headers(adult))).json()[
                    "operations"
                ]
            )
            == 1
        )
        backup = f"/v1/families/{fid}/personal-backup"
        blob = b"SART\x02" + os.urandom(150)
        headers = {**api.headers(adult), "X-Backup-Revision": "0"}
        assert (await client.put(backup, headers=headers, content=blob)).status_code == 204
        assert (await client.get(backup, headers=api.headers(adult))).content == blob
        assert (await client.get(backup, headers=api.headers(owner))).status_code == 404
        assert (await client.get(backup, headers=api.headers(stranger))).status_code == 404
        assert (await client.delete(backup, headers=api.headers(owner))).status_code == 204
        assert (await client.get(backup, headers=api.headers(adult))).content == blob
        assert (await client.put(backup, headers=headers, content=blob)).status_code == 409
        with engine.connect() as connection:
            assert connection.execute(
                select(resources.c.private_adult_id).where(resources.c.id == UUID(rid))
            ).scalar_one() == UUID(adult["adult_id"])
            assert (
                connection.execute(
                    select(personal_backups.c.ciphertext).where(
                        personal_backups.c.family_id == UUID(fid)
                    )
                ).scalar_one()
                == blob
            )
        with engine.begin() as connection:
            advance_replacement_epochs(connection, UUID(owner["adult_id"]))
            assert (
                connection.execute(
                    select(resources.c.key_epoch).where(resources.c.id == UUID(rid))
                ).scalar_one()
                == 1
            )
            advance_replacement_epochs(connection, UUID(adult["adult_id"]))
            assert (
                connection.execute(
                    select(resources.c.key_epoch).where(resources.c.id == UUID(rid))
                ).scalar_one()
                == 2
            )
        assert (
            await client.post(
                "/v1/key-grants", headers=api.headers(adult), json=grant(adult["device_id"])
            )
        ).status_code == 409
        with engine.begin() as connection:
            connection.execute(
                update(memberships)
                .where(
                    memberships.c.family_id == UUID(fid),
                    memberships.c.adult_id == UUID(adult["adult_id"]),
                )
                .values(status="revoked")
            )
            advance_replacement_epochs(connection, UUID(adult["adult_id"]))
            assert (
                connection.execute(
                    select(resources.c.key_epoch).where(resources.c.id == UUID(rid))
                ).scalar_one()
                == 3
            )
        with engine.begin() as connection:
            connection.execute(
                update(devices)
                .where(devices.c.id == UUID(adult["device_id"]))
                .values(state="revoked")
            )
        assert (await client.get(backup, headers=api.headers(adult))).status_code == 401
        with engine.begin() as connection:
            connection.execute(
                update(families)
                .where(families.c.id == UUID(fid))
                .values(deleted_at=datetime.now(UTC))
            )
            assert (
                connection.execute(
                    select(personal_backups).where(personal_backups.c.family_id == UUID(fid))
                ).first()
                is None
            )
    engine.dispose()
    database.close()


def test_personal_calendar_owner_isolation_replay_and_backup() -> None:
    asyncio.run(flow())
