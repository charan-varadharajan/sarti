"""BUG-003 prepared households: metadata, grants, isolation and relay contracts."""

import asyncio
import hashlib
import os
from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from httpx import ASGITransport, AsyncClient
from sqlalchemy import create_engine, select, update
from test_stage2_api import Api, StubWebAuthn, b64

from sarti_backend.api.sync import _grant_message
from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import devices, key_grants, memberships, permissions, resources
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


async def child_flow() -> None:
    url = os.environ["SARTI_DATABASE_URL"]
    database = Database(url)
    engine = create_engine(url)
    app = create_app(Settings(environment="test", database_url=url), database, StubWebAuthn())
    signing = Ed25519PrivateKey.generate()
    guardian_signing = Ed25519PrivateKey.generate()
    guardian_public = guardian_signing.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    )
    public = signing.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        owner = await api.register(str(uuid4()), public)
        guardian = await api.register(str(uuid4()), guardian_public)
        outsider = await api.register(str(uuid4()))
        pending = await api.register(str(uuid4()))
        revoked = await api.register(str(uuid4()))
        family = (await client.post("/v1/families", headers=api.headers(owner), json={})).json()
        other = (await client.post("/v1/families", headers=api.headers(outsider), json={})).json()
        family_id = family["id"]
        calendar = next(r["id"] for r in family["resources"] if r["kind"] == "calendar")
        child_id = str(uuid4())
        path = f"/v1/families/{family_id}/resources"
        directory = f"{path}/{child_id}/devices"
        payload = {"kind": "child_profile", "resource_id": child_id}
        assert (await client.post(path, json=payload)).status_code == 401
        assert (
            await client.post(path, headers=api.headers(outsider), json=payload)
        ).status_code == 404
        created = await client.post(path, headers=api.headers(owner), json=payload)
        assert created.status_code == 201, created.text
        assert created.json() == {"id": child_id, "kind": "child_profile", "key_epoch": 1}
        assert (
            await client.post(path, headers=api.headers(owner), json=payload)
        ).json() == created.json()
        assert (
            await client.post(
                path,
                headers=api.headers(owner),
                json={"kind": "child_profile", "resource_id": calendar},
            )
        ).status_code == 409
        assert (
            await client.post(path, headers=api.headers(owner), json=dict(payload, name="Mia"))
        ).status_code == 422
        assert (
            await client.post(
                f"/v1/families/{other['id']}/resources",
                headers=api.headers(outsider),
                json=payload,
            )
        ).status_code == 409
        with engine.begin() as connection:
            for person, status in ((guardian, "active"), (pending, "pending"), (revoked, "active")):
                connection.execute(
                    memberships.insert().values(
                        family_id=UUID(family_id),
                        adult_id=UUID(person["adult_id"]),
                        role="guardian",
                        status=status,
                        created_at=datetime.now(UTC),
                    )
                )
                connection.execute(
                    permissions.insert().values(
                        resource_id=UUID(calendar),
                        adult_id=UUID(person["adult_id"]),
                        permission="read",
                    )
                )
            connection.execute(
                update(devices)
                .where(devices.c.id == UUID(revoked["device_id"]))
                .values(state="revoked")
            )
        assert (
            await client.post(path, headers=api.headers(guardian), json={"kind": "child_profile"})
        ).status_code == 403
        assert (await client.get(directory, headers=api.headers(outsider))).status_code == 404
        assert (await client.get(directory, headers=api.headers(pending))).status_code == 404
        assert (await client.get(directory, headers=api.headers(guardian))).status_code == 403
        assert (await client.get(directory, headers=api.headers(revoked))).status_code == 401
        listed = await client.get(directory, headers=api.headers(owner))
        assert [d["device_id"] for d in listed.json()] == [owner["device_id"]]
        assert listed.json()[0]["permission"] == "admin"
        shared_id = str(uuid4())
        shared_payload = {
            "kind": "child_profile",
            "resource_id": shared_id,
            "share_with_calendar_guardians": True,
        }
        shared = await client.post(path, headers=api.headers(owner), json=shared_payload)
        assert shared.status_code == 201
        shared_directory = f"{path}/{shared_id}/devices"
        shared_devices = (await client.get(shared_directory, headers=api.headers(owner))).json()
        assert {d["device_id"] for d in shared_devices} == {
            owner["device_id"],
            guardian["device_id"],
        }
        assert (
            next(d["permission"] for d in shared_devices if d["device_id"] == guardian["device_id"])
            == "read"
        )
        # A later guardian must not gain access through a retry of earlier consent.
        with engine.begin() as connection:
            connection.execute(
                update(memberships)
                .where(
                    (memberships.c.family_id == UUID(family_id))
                    & (memberships.c.adult_id == UUID(pending["adult_id"]))
                )
                .values(status="active")
            )
        assert (
            await client.post(path, headers=api.headers(owner), json=shared_payload)
        ).status_code == 201
        assert (await client.get(shared_directory, headers=api.headers(pending))).status_code == 403
        with engine.begin() as connection:
            connection.execute(
                update(memberships)
                .where(
                    (memberships.c.family_id == UUID(family_id))
                    & (memberships.c.adult_id == UUID(pending["adult_id"]))
                )
                .values(status="pending")
            )
        wrapped = os.urandom(80)  # API verifies signatures; mobile tests verify sealed-box crypto.

        def grant(recipient: dict[str, str], epoch: int = 1) -> dict[str, object]:
            return {
                "family_id": family_id,
                "resource_id": child_id,
                "key_epoch": epoch,
                "recipient_device_id": recipient["device_id"],
                "wrapped_key": b64(wrapped),
                "signature": b64(
                    signing.sign(
                        _grant_message(
                            UUID(child_id),
                            epoch,
                            UUID(recipient["device_id"]),
                            UUID(owner["device_id"]),
                            wrapped,
                        )
                    )
                ),
            }

        for person in (outsider, pending, guardian, revoked):
            assert (
                await client.post("/v1/key-grants", headers=api.headers(owner), json=grant(person))
            ).status_code in (403, 404)
        # Explicit read permission is necessary; creating a child never grants it implicitly.
        with engine.begin() as connection:
            connection.execute(
                permissions.insert().values(
                    resource_id=UUID(child_id),
                    adult_id=UUID(guardian["adult_id"]),
                    permission="read",
                )
            )
        allowed = (await client.get(directory, headers=api.headers(guardian))).json()
        assert {d["device_id"] for d in allowed} == {owner["device_id"], guardian["device_id"]}
        bad = dict(grant(guardian), signature=b64(bytes(64)))
        assert (
            await client.post("/v1/key-grants", headers=api.headers(owner), json=bad)
        ).status_code == 403
        assert (
            await client.post("/v1/key-grants", headers=api.headers(guardian), json=grant(owner))
        ).status_code == 403
        first = await client.post(
            "/v1/key-grants", headers=api.headers(owner), json=grant(guardian)
        )
        assert first.status_code == 201, first.text
        retry = await client.post(
            "/v1/key-grants", headers=api.headers(owner), json=grant(guardian)
        )
        different = bytes([wrapped[0] ^ 1]) + wrapped[1:]
        conflicting = dict(
            grant(guardian),
            wrapped_key=b64(different),
            signature=b64(
                signing.sign(
                    _grant_message(
                        UUID(child_id),
                        1,
                        UUID(guardian["device_id"]),
                        UUID(owner["device_id"]),
                        different,
                    )
                )
            ),
        )
        assert (
            await client.post("/v1/key-grants", headers=api.headers(owner), json=conflicting)
        ).status_code == 409
        for invalid in (
            dict(grant(guardian), wrapped_key="?" * 107),
            dict(grant(guardian), key_epoch=2**63),
        ):
            assert (
                await client.post("/v1/key-grants", headers=api.headers(owner), json=invalid)
            ).status_code == 422
        assert retry.json() == first.json()
        assert (await client.get("/v1/key-grants", headers=api.headers(guardian))).json() == [
            first.json()
        ]
        assert (await client.get("/v1/key-grants", headers=api.headers(outsider))).json() == []
        assert any(
            d["has_current_grant"]
            for d in (await client.get(directory, headers=api.headers(owner))).json()
        )
        with engine.begin() as connection:
            connection.execute(
                permissions.delete().where(
                    (permissions.c.resource_id == UUID(child_id))
                    & (permissions.c.adult_id == UUID(guardian["adult_id"]))
                )
            )
        assert (await client.get("/v1/key-grants", headers=api.headers(guardian))).json() == []
        nonce, ciphertext = os.urandom(24), os.urandom(80)

        def operation(resource: str, sequence: int) -> dict[str, object]:
            return {
                "operation_id": str(uuid4()),
                "family_id": family_id,
                "resource_id": resource,
                "device_sequence": sequence,
                "key_epoch": 1,
                "logical_version": {owner["device_id"]: sequence},
                "nonce": b64(nonce),
                "ciphertext": b64(ciphertext),
                "content_digest": b64(hashlib.sha256(nonce + ciphertext).digest()),
            }

        child_op = operation(child_id, 1)
        event_op = operation(calendar, 2)
        for op in (child_op, event_op):
            assert (
                await client.post("/v1/sync/operations", headers=api.headers(owner), json=op)
            ).status_code == 201
        for field, value in (
            ("resource_id", calendar),
            ("logical_version", {owner["device_id"]: 8}),
            ("family_id", other["id"]),
        ):
            response = await client.post(
                "/v1/sync/operations",
                headers=api.headers(owner),
                json=dict(child_op, **{field: value}),
            )
            assert response.status_code in (409, 404)
        # A filtered-only page advances, allowing the next calendar page to be fetched.
        page = (
            await client.get(
                f"/v1/families/{family_id}/sync?limit=1", headers=api.headers(guardian)
            )
        ).json()
        assert page["operations"] == [] and page["next_cursor"] > 0
        page2 = (
            await client.get(
                f"/v1/families/{family_id}/sync?cursor={page['next_cursor']}",
                headers=api.headers(guardian),
            )
        ).json()
        assert [o["operation_id"] for o in page2["operations"]] == [event_op["operation_id"]]
        with engine.begin() as connection:
            connection.execute(
                permissions.insert().values(
                    resource_id=UUID(child_id),
                    adult_id=UUID(guardian["adult_id"]),
                    permission="read",
                )
            )
            connection.execute(
                update(devices)
                .where(devices.c.id == UUID(owner["device_id"]))
                .values(state="revoked")
            )
        assert (await client.get("/v1/key-grants", headers=api.headers(guardian))).json() == []
        with engine.begin() as connection:
            connection.execute(
                update(devices)
                .where(devices.c.id == UUID(owner["device_id"]))
                .values(state="active")
            )
            connection.execute(
                update(resources).where(resources.c.id == UUID(child_id)).values(key_epoch=2)
            )
        assert (await client.get("/v1/key-grants", headers=api.headers(guardian))).json() == []
        assert (
            await client.post("/v1/key-grants", headers=api.headers(owner), json=grant(guardian))
        ).status_code == 409
        # An old receipt can be acknowledged without accepting new stale data.
        acknowledged = await client.post(
            "/v1/sync/operations", headers=api.headers(owner), json=child_op
        )
        assert acknowledged.status_code == 201 and acknowledged.json()["duplicate"] is True
        stale_new = dict(child_op, operation_id=str(uuid4()), device_sequence=3)
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(owner), json=stale_new)
        ).status_code == 409
        # Epoch initialization is serialized: another admin cannot publish a
        # different origin key before receiving the first admin's sealed grant.
        with engine.begin() as connection:
            connection.execute(
                update(permissions)
                .where(
                    (permissions.c.resource_id == UUID(child_id))
                    & (permissions.c.adult_id == UUID(guardian["adult_id"]))
                )
                .values(permission="admin")
            )
        assert (
            await client.post("/v1/key-grants", headers=api.headers(owner), json=grant(owner, 2))
        ).status_code == 201
        extra_guardian = {"device_id": outsider["device_id"]}
        with engine.begin() as connection:
            connection.execute(
                memberships.insert().values(
                    family_id=UUID(family_id),
                    adult_id=UUID(outsider["adult_id"]),
                    role="guardian",
                    status="active",
                    created_at=datetime.now(UTC),
                )
            )
            connection.execute(
                permissions.insert().values(
                    resource_id=UUID(child_id),
                    adult_id=UUID(outsider["adult_id"]),
                    permission="read",
                )
            )
        racing = grant(extra_guardian, 2)
        racing["signature"] = b64(
            guardian_signing.sign(
                _grant_message(
                    UUID(child_id),
                    2,
                    UUID(extra_guardian["device_id"]),
                    UUID(guardian["device_id"]),
                    wrapped,
                )
            )
        )
        assert (
            await client.post("/v1/key-grants", headers=api.headers(guardian), json=racing)
        ).status_code == 409
        assert (
            await client.post("/v1/key-grants", headers=api.headers(owner), json=grant(guardian, 2))
        ).status_code == 201
        assert (
            await client.post("/v1/key-grants", headers=api.headers(guardian), json=racing)
        ).status_code == 201
        with engine.begin() as connection:
            connection.execute(
                update(memberships)
                .where(
                    (memberships.c.family_id == UUID(family_id))
                    & (memberships.c.adult_id == UUID(guardian["adult_id"]))
                )
                .values(status="revoked")
            )
        assert (
            await client.post("/v1/key-grants", headers=api.headers(owner), json=grant(guardian, 2))
        ).status_code == 403
        with engine.connect() as connection:
            rows = connection.execute(
                select(key_grants).where(key_grants.c.resource_id == UUID(child_id))
            ).all()
            assert len(rows) == 4
    engine.dispose()
    database.close()


def test_child_resource_grants_and_restricted_relay_security() -> None:
    asyncio.run(child_flow())
