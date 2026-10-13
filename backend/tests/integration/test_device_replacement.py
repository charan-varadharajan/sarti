"""BUG-010: prepared real-PostgreSQL replacement and independent crypto checks."""

import asyncio
import hashlib
import os
from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from nacl.bindings import (
    crypto_aead_xchacha20poly1305_ietf_decrypt,
    crypto_aead_xchacha20poly1305_ietf_encrypt,
)
from nacl.exceptions import CryptoError
from nacl.public import PrivateKey, SealedBox
from nacl.signing import SigningKey
from sqlalchemy import select, update
from test_stage2_api import Api, StubWebAuthn, b64

from sarti_backend.api import auth
from sarti_backend.api.sync import _grant_message
from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import credentials, devices, memberships, permissions, resources
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


async def replacement_payload(client: AsyncClient, credential: str) -> dict:
    options = (await client.post("/v1/auth/authentication/options")).json()
    return {
        "challenge_id": options["challenge_id"],
        "credential": {
            "id": b64(credential.encode()),
            "challenge": options["public_key"]["challenge"],
        },
        "device_keys": {
            "encryption_public_key": b64(bytes(PrivateKey.generate().public_key)),
            "signing_public_key": b64(bytes(SigningKey.generate().verify_key)),
        },
    }


async def flow() -> None:
    url = os.environ["SARTI_DATABASE_URL"]
    database = Database(url)
    app = create_app(Settings(environment="test", database_url=url), database, StubWebAuthn())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        credential = str(uuid4())
        owner_sign = SigningKey.generate()
        owner = await api.register(credential, bytes(owner_sign.verify_key))
        old_box = PrivateKey.generate()
        with database.transaction() as c:
            c.execute(
                update(devices)
                .where(devices.c.id == UUID(owner["device_id"]))
                .values(encryption_public_key=bytes(old_box.public_key))
            )
        guardian_sign = SigningKey.generate()
        guardian_credential = str(uuid4())
        guardian = await api.register(guardian_credential, bytes(guardian_sign.verify_key))
        outsider = await api.register(str(uuid4()))
        family = (await client.post("/v1/families", headers=api.headers(owner), json={})).json()
        other = (await client.post("/v1/families", headers=api.headers(outsider), json={})).json()
        child = (
            await client.post(
                f"/v1/families/{family['id']}/resources",
                headers=api.headers(owner),
                json={"kind": "child_profile"},
            )
        ).json()
        calendar = next(r for r in family["resources"] if r["kind"] == "calendar")
        with database.transaction() as c:
            c.execute(
                memberships.insert().values(
                    family_id=UUID(other["id"]),
                    adult_id=UUID(owner["adult_id"]),
                    role="guardian",
                    status="pending",
                    created_at=datetime.now(UTC),
                )
            )
            c.execute(
                memberships.insert().values(
                    family_id=UUID(family["id"]),
                    adult_id=UUID(guardian["adult_id"]),
                    role="guardian",
                    status="active",
                    created_at=datetime.now(UTC),
                )
            )
            c.execute(
                permissions.insert().values(
                    resource_id=UUID(calendar["id"]),
                    adult_id=UUID(guardian["adult_id"]),
                    permission="admin",
                )
            )
        old_key = os.urandom(32)
        old_wrapped = SealedBox(old_box.public_key).encrypt(old_key)
        old_grant = {
            "family_id": family["id"],
            "resource_id": calendar["id"],
            "key_epoch": 1,
            "recipient_device_id": owner["device_id"],
            "wrapped_key": b64(old_wrapped),
            "signature": b64(
                owner_sign.sign(
                    _grant_message(
                        UUID(calendar["id"]),
                        1,
                        UUID(owner["device_id"]),
                        UUID(owner["device_id"]),
                        old_wrapped,
                    )
                ).signature
            ),
        }
        assert (
            await client.post("/v1/key-grants", headers=api.headers(owner), json=old_grant)
        ).status_code == 201
        assert SealedBox(old_box).decrypt(old_wrapped) == old_key
        payload = await replacement_payload(client, credential)
        bad = dict(payload, credential=dict(payload["credential"], challenge="wrong"))
        assert (await client.post("/v1/auth/authentication/complete", json=bad)).status_code == 401
        assert all(
            r["key_epoch"] == 1
            for r in (await client.get("/v1/families", headers=api.headers(owner))).json()[0][
                "resources"
            ]
        )
        box = PrivateKey.generate()
        signing = SigningKey.generate()
        payload["device_keys"] = {
            "encryption_public_key": b64(bytes(box.public_key)),
            "signing_public_key": b64(bytes(signing.verify_key)),
        }
        response = await client.post("/v1/auth/authentication/complete", json=payload)
        assert response.status_code == 200
        replacement = response.json()
        assert (await client.get("/v1/families", headers=api.headers(owner))).status_code == 401
        assert (await client.get("/v1/key-grants", headers=api.headers(owner))).status_code == 401
        assert (
            await client.post("/v1/auth/authentication/complete", json=payload)
        ).status_code == 401
        listed = (await client.get("/v1/families", headers=api.headers(replacement))).json()[0]
        assert {r["id"]: r["key_epoch"] for r in listed["resources"]} == {
            r["id"]: 2 for r in [*family["resources"], child]
        }
        assert all(
            r["key_epoch"] == 1
            for r in (await client.get("/v1/families", headers=api.headers(outsider))).json()[0][
                "resources"
            ]
        )
        directory = (
            await client.get(
                f"/v1/families/{family['id']}/resources/{calendar['id']}/devices",
                headers=api.headers(guardian),
            )
        ).json()
        assert {d["device_id"] for d in directory} == {
            guardian["device_id"],
            replacement["device_id"],
        }
        new_key = os.urandom(32)
        wrapped = SealedBox(box.public_key).encrypt(new_key)
        grant = {
            "family_id": family["id"],
            "resource_id": calendar["id"],
            "key_epoch": 2,
            "recipient_device_id": replacement["device_id"],
            "wrapped_key": b64(wrapped),
            "signature": b64(
                guardian_sign.sign(
                    _grant_message(
                        UUID(calendar["id"]),
                        2,
                        UUID(replacement["device_id"]),
                        UUID(guardian["device_id"]),
                        wrapped,
                    )
                ).signature
            ),
        }
        assert (
            await client.post(
                "/v1/key-grants", headers=api.headers(guardian), json=dict(grant, key_epoch=1)
            )
        ).status_code == 409
        assert (
            await client.post(
                "/v1/key-grants",
                headers=api.headers(guardian),
                json=dict(grant, recipient_device_id=owner["device_id"]),
            )
        ).status_code == 403
        assert (
            await client.post("/v1/key-grants", headers=api.headers(guardian), json=grant)
        ).status_code == 201
        delivered = (await client.get("/v1/key-grants", headers=api.headers(replacement))).json()
        assert len(delivered) == 1
        assert SealedBox(box).decrypt(wrapped) == new_key
        with pytest.raises(CryptoError):
            SealedBox(old_box).decrypt(wrapped)
        nonce = os.urandom(24)
        aad = b"prepared-epoch-two"
        ciphertext = crypto_aead_xchacha20poly1305_ietf_encrypt(
            b"private prepared activity", aad, nonce, new_key
        )
        assert (
            crypto_aead_xchacha20poly1305_ietf_decrypt(ciphertext, aad, nonce, new_key)
            == b"private prepared activity"
        )
        with pytest.raises(CryptoError):
            crypto_aead_xchacha20poly1305_ietf_decrypt(ciphertext, aad, nonce, old_key)
        operation = {
            "operation_id": str(uuid4()),
            "family_id": family["id"],
            "resource_id": calendar["id"],
            "device_sequence": 1,
            "key_epoch": 1,
            "logical_version": {guardian["device_id"]: 1},
            "nonce": b64(nonce),
            "ciphertext": b64(ciphertext),
            "content_digest": b64(hashlib.sha256(nonce + ciphertext).digest()),
        }
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(guardian), json=operation)
        ).status_code == 409
        operation["key_epoch"] = 2
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(guardian), json=operation)
        ).status_code == 201
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(owner), json=operation)
        ).status_code == 401
        assert (
            await client.get(f"/v1/families/{family['id']}/sync", headers=api.headers(owner))
        ).status_code == 401
        # A restricted guardian replacement rotates only its accessible resource.
        guardian_payload = await replacement_payload(client, guardian_credential)
        assert (
            await client.post("/v1/auth/authentication/complete", json=guardian_payload)
        ).status_code == 200
        listed = (await client.get("/v1/families", headers=api.headers(replacement))).json()[0]
        assert {r["id"]: r["key_epoch"] for r in listed["resources"]} == {
            r["id"]: (3 if r["id"] == calendar["id"] else 2) for r in [*family["resources"], child]
        }
        assert all(
            r["key_epoch"] == 1
            for r in (await client.get("/v1/families", headers=api.headers(outsider))).json()[0][
                "resources"
            ]
        )
    database.close()


def test_replacement_epochs_grants_stale_writes_and_future_ciphertext() -> None:
    asyncio.run(flow())


async def atomic_flow(monkeypatch: pytest.MonkeyPatch, concurrent: bool) -> None:
    url = os.environ["SARTI_DATABASE_URL"]
    database = Database(url)
    app = create_app(Settings(environment="test", database_url=url), database, StubWebAuthn())
    async with AsyncClient(
        transport=ASGITransport(app=app, raise_app_exceptions=False), base_url="http://test"
    ) as client:
        api = Api(client)
        credential = str(uuid4())
        owner = await api.register(credential)
        family = (await client.post("/v1/families", headers=api.headers(owner), json={})).json()
        if concurrent:
            other_credential = str(uuid4())
            with database.transaction() as c:
                c.execute(
                    credentials.insert().values(
                        credential_id=other_credential.encode(),
                        adult_id=UUID(owner["adult_id"]),
                        public_key=b"prepared-other-passkey",
                        sign_count=0,
                        created_at=datetime.now(UTC),
                    )
                )
            payloads = [
                await replacement_payload(client, value) for value in (credential, other_credential)
            ]
            results = await asyncio.gather(
                *(client.post("/v1/auth/authentication/complete", json=p) for p in payloads)
            )
            assert [r.status_code for r in results] == [200, 200]
            with database.connect() as c:
                assert (
                    len(
                        c.execute(
                            select(devices.c.id).where(
                                (devices.c.adult_id == UUID(owner["adult_id"]))
                                & (devices.c.state == "active")
                            )
                        ).all()
                    )
                    == 1
                )
                assert set(
                    c.execute(
                        select(resources.c.key_epoch).where(
                            resources.c.family_id == UUID(family["id"])
                        )
                    ).scalars()
                ) == {3}
        else:
            payload = await replacement_payload(client, credential)
            original = auth._new_session

            def interrupted(*args, **kwargs):
                raise RuntimeError("prepared interruption")

            monkeypatch.setattr(auth, "_new_session", interrupted)
            assert (
                await client.post("/v1/auth/authentication/complete", json=payload)
            ).status_code == 500
            assert (await client.get("/v1/families", headers=api.headers(owner))).status_code == 200
            with database.connect() as c:
                assert set(
                    c.execute(
                        select(resources.c.key_epoch).where(
                            resources.c.family_id == UUID(family["id"])
                        )
                    ).scalars()
                ) == {1}
            monkeypatch.setattr(auth, "_new_session", original)
            assert (
                await client.post("/v1/auth/authentication/complete", json=payload)
            ).status_code == 200
    database.close()


def test_interrupted_replacement_rolls_back_and_can_retry(monkeypatch: pytest.MonkeyPatch) -> None:
    asyncio.run(atomic_flow(monkeypatch, False))


def test_concurrent_replacements_serialize(monkeypatch: pytest.MonkeyPatch) -> None:
    asyncio.run(atomic_flow(monkeypatch, True))
