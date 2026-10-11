import asyncio
import base64
import hashlib
import os
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from httpx import ASGITransport, AsyncClient
from sqlalchemy import create_engine, text

from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.identity.webauthn_service import (
    VerifiedAuthentication,
    VerifiedRegistration,
)
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


def b64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


class StubWebAuthn:
    def registration_options(
        self, *, challenge: bytes, user_id: bytes, user_name: str
    ) -> dict[str, Any]:
        return {"challenge": b64(challenge), "user": {"id": b64(user_id), "name": user_name}}

    def verify_registration(
        self, *, credential: dict[str, Any], challenge: bytes
    ) -> VerifiedRegistration:
        if credential.get("challenge") != b64(challenge):
            raise ValueError("challenge mismatch")
        credential_id = str(credential["id"]).encode()
        return VerifiedRegistration(credential_id, b"public-key-" + credential_id, 0)

    def authentication_options(self, *, challenge: bytes) -> dict[str, Any]:
        return {"challenge": b64(challenge)}

    def verify_authentication(
        self,
        *,
        credential: dict[str, Any],
        challenge: bytes,
        credential_public_key: bytes,
        current_sign_count: int,
    ) -> VerifiedAuthentication:
        if credential.get("challenge") != b64(challenge) or not credential_public_key:
            raise ValueError("invalid assertion")
        return VerifiedAuthentication(current_sign_count + 1)


class Api:
    def __init__(self, client: AsyncClient) -> None:
        self.client = client

    async def register(
        self, credential_id: str, signing_public_key: bytes | None = None
    ) -> dict[str, Any]:
        options = await self.client.post("/v1/auth/registration/options")
        assert options.status_code == 200
        body = options.json()
        complete = await self.client.post(
            "/v1/auth/registration/complete",
            json={
                "challenge_id": body["challenge_id"],
                "credential": {
                    "id": credential_id,
                    "challenge": body["public_key"]["challenge"],
                },
                "device_keys": {
                    "encryption_public_key": b64(b"e" * 32),
                    "signing_public_key": b64(signing_public_key or b"s" * 32),
                },
            },
        )
        assert complete.status_code == 201, complete.text
        return complete.json()

    @staticmethod
    def headers(session: dict[str, Any]) -> dict[str, str]:
        return {"Authorization": f"Bearer {session['session_token']}"}


async def _request_flow() -> None:
    database_url = os.environ["SARTI_DATABASE_URL"]
    engine = create_engine(database_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                "TRUNCATE sync_operations, resource_key_grants, guardian_invitations, "
                "resource_permissions, resources, memberships, families, sessions, "
                "devices, webauthn_credentials, webauthn_challenges, adults CASCADE"
            )
        )
    engine.dispose()

    database = Database(database_url)
    app = create_app(
        Settings(environment="test", database_url=database_url),
        database,
        StubWebAuthn(),
    )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        owner_signing_key = Ed25519PrivateKey.generate()
        owner_public_key = owner_signing_key.public_key().public_bytes(
            serialization.Encoding.Raw,
            serialization.PublicFormat.Raw,
        )
        owner = await api.register("owner-credential", owner_public_key)
        guardian = await api.register("guardian-credential")
        outsider = await api.register("outsider-credential")

        family_response = await client.post("/v1/families", headers=api.headers(owner))
        assert family_response.status_code == 201
        family = family_response.json()
        family_id = family["id"]
        calendar = next(item for item in family["resources"] if item["kind"] == "calendar")

        child = await client.post(
            f"/v1/families/{family_id}/resources",
            headers=api.headers(owner),
            json={"kind": "child_profile"},
        )
        assert child.status_code == 201

        outsider_read = await client.get(
            f"/v1/families/{family_id}/sync", headers=api.headers(outsider)
        )
        assert outsider_read.status_code == 404

        invitation = await client.post(
            f"/v1/families/{family_id}/invitations", headers=api.headers(owner)
        )
        assert invitation.status_code == 201
        invite = invitation.json()
        accepted = await client.post(
            "/v1/invitations/accept",
            headers=api.headers(guardian),
            json={"token": invite["token"]},
        )
        assert accepted.status_code == 200
        duplicate_accept = await client.post(
            "/v1/invitations/accept",
            headers=api.headers(outsider),
            json={"token": invite["token"]},
        )
        assert duplicate_accept.status_code == 404

        permission_payload = {
            "permissions": [
                {"resource_id": resource["id"], "permission": "admin"}
                for resource in [*family["resources"], child.json()]
            ]
        }
        approved = await client.post(
            f"/v1/families/{family_id}/invitations/{invite['id']}/approve",
            headers=api.headers(owner),
            json=permission_payload,
        )
        assert approved.status_code == 200, approved.text

        wrapped_key = b"w" * 80
        grant_message = b"".join(
            (
                b"SARTI-GRANT-V1\0",
                UUID(calendar["id"]).bytes,
                (1).to_bytes(8, "big"),
                UUID(guardian["device_id"]).bytes,
                UUID(owner["device_id"]).bytes,
                hashlib.sha256(wrapped_key).digest(),
            )
        )
        key_grant = await client.post(
            "/v1/key-grants",
            headers=api.headers(owner),
            json={
                "family_id": family_id,
                "resource_id": calendar["id"],
                "key_epoch": 1,
                "recipient_device_id": guardian["device_id"],
                "wrapped_key": b64(wrapped_key),
                "signature": b64(owner_signing_key.sign(grant_message)),
            },
        )
        assert key_grant.status_code == 201, key_grant.text
        grants = await client.get("/v1/key-grants", headers=api.headers(guardian))
        assert grants.status_code == 200
        assert len(grants.json()) == 1

        nonce = b"n" * 24
        ciphertext = b"encrypted-event-payload"
        digest = hashlib.sha256(nonce + ciphertext).digest()
        operation_id = str(uuid4())
        operation = {
            "operation_id": operation_id,
            "family_id": family_id,
            "resource_id": calendar["id"],
            "device_sequence": 1,
            "key_epoch": 1,
            "logical_version": {owner["device_id"]: 1},
            "nonce": b64(nonce),
            "ciphertext": b64(ciphertext),
            "content_digest": b64(digest),
        }
        uploaded = await client.post(
            "/v1/sync/operations", headers=api.headers(owner), json=operation
        )
        assert uploaded.status_code == 201, uploaded.text
        assert uploaded.json()["duplicate"] is False
        duplicate = await client.post(
            "/v1/sync/operations", headers=api.headers(owner), json=operation
        )
        assert duplicate.status_code == 201
        assert duplicate.json()["duplicate"] is True

        replay = dict(operation, operation_id=str(uuid4()))
        replayed = await client.post("/v1/sync/operations", headers=api.headers(owner), json=replay)
        assert replayed.status_code == 409
        malformed = dict(
            operation, operation_id=str(uuid4()), device_sequence=2, content_digest=b64(b"x" * 32)
        )
        rejected = await client.post(
            "/v1/sync/operations", headers=api.headers(owner), json=malformed
        )
        assert rejected.status_code == 409

        downloaded = await client.get(
            f"/v1/families/{family_id}/sync", headers=api.headers(guardian)
        )
        assert downloaded.status_code == 200
        assert [item["operation_id"] for item in downloaded.json()["operations"]] == [operation_id]

        revoked = await client.delete(
            f"/v1/families/{family_id}/guardians/{guardian['adult_id']}",
            headers=api.headers(owner),
        )
        assert revoked.status_code == 200
        assert revoked.json()["new_key_epoch"] == 2
        after_revocation = await client.get(
            f"/v1/families/{family_id}/sync", headers=api.headers(guardian)
        )
        assert after_revocation.status_code == 404
        revoked_grant_message = b"".join(
            (
                b"SARTI-GRANT-V1\0",
                UUID(calendar["id"]).bytes,
                (2).to_bytes(8, "big"),
                UUID(guardian["device_id"]).bytes,
                UUID(owner["device_id"]).bytes,
                hashlib.sha256(wrapped_key).digest(),
            )
        )
        revoked_grant = await client.post(
            "/v1/key-grants",
            headers=api.headers(owner),
            json={
                "family_id": family_id,
                "resource_id": calendar["id"],
                "key_epoch": 2,
                "recipient_device_id": guardian["device_id"],
                "wrapped_key": b64(wrapped_key),
                "signature": b64(owner_signing_key.sign(revoked_grant_message)),
            },
        )
        assert revoked_grant.status_code == 403
        stale_operation = dict(operation, operation_id=str(uuid4()), device_sequence=2)
        stale = await client.post(
            "/v1/sync/operations", headers=api.headers(owner), json=stale_operation
        )
        assert stale.status_code == 409

        expired_at = datetime.now(UTC) - timedelta(seconds=1)
        with create_engine(database_url).begin() as connection:
            connection.execute(
                text("UPDATE sync_operations SET expires_at = :expired_at"),
                {"expired_at": expired_at},
            )
        fresh_ciphertext = b"another-encrypted-operation"
        fresh_nonce = b"q" * 24
        fresh = dict(
            operation,
            operation_id=str(uuid4()),
            device_sequence=2,
            key_epoch=2,
            nonce=b64(fresh_nonce),
            ciphertext=b64(fresh_ciphertext),
            content_digest=b64(hashlib.sha256(fresh_nonce + fresh_ciphertext).digest()),
        )
        assert (
            await client.post("/v1/sync/operations", headers=api.headers(owner), json=fresh)
        ).status_code == 201
        with create_engine(database_url).connect() as connection:
            count = connection.execute(text("SELECT count(*) FROM sync_operations")).scalar_one()
        assert count == 1

        auth_options = await client.post("/v1/auth/authentication/options")
        auth_body = auth_options.json()
        replacement_payload = {
            "challenge_id": auth_body["challenge_id"],
            "credential": {
                "id": b64(b"owner-credential"),
                "challenge": auth_body["public_key"]["challenge"],
            },
            "device_keys": {
                "encryption_public_key": b64(b"2" * 32),
                "signing_public_key": b64(b"3" * 32),
            },
        }
        replaced = await client.post(
            "/v1/auth/authentication/complete",
            json=replacement_payload,
        )
        assert replaced.status_code == 200, replaced.text
        replayed_auth = await client.post(
            "/v1/auth/authentication/complete",
            json=replacement_payload,
        )
        assert replayed_auth.status_code == 401
        old_session = await client.get("/v1/families", headers=api.headers(owner))
        assert old_session.status_code == 401


def test_stage2_identity_household_and_encrypted_relay_flow() -> None:
    asyncio.run(_request_flow())
