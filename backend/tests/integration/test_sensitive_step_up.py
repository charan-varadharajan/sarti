"""S5-AUTH/DEVICE/ROLE: real PostgreSQL; WebAuthn mocked only at verifier boundary."""

import asyncio
import hashlib
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from fastapi import Request
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select, update
from test_stage2_api import Api, StubWebAuthn, b64

from sarti_backend.core.auth import AuthenticatedDevice
from sarti_backend.core.config import Settings
from sarti_backend.core.errors import ApiError
from sarti_backend.db.database import Database
from sarti_backend.db.schema import devices, families, sensitive_authorizations, sessions
from sarti_backend.identity.step_up import consume_step_up
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


def request_for(token: str) -> Request:
    return Request({"type": "http", "headers": [(b"authorization", f"Bearer {token}".encode())]})


async def flow() -> None:
    database = Database(os.environ["SARTI_DATABASE_URL"])
    app = create_app(
        Settings(database_url=os.environ["SARTI_DATABASE_URL"]),
        database=database,
        webauthn=StubWebAuthn(),
    )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        credential = str(uuid4())
        options = (await client.post("/v1/auth/registration/options")).json()
        assert options["public_key"]["user"]["name"].startswith("account-")
        owner = await api.register(credential)
        outsider_credential = str(uuid4())
        outsider = await api.register(outsider_credential)
        headers = api.headers(owner)
        family = (await client.post("/v1/families", headers=headers)).json()
        family_id = UUID(family["id"])
        target = UUID(owner["adult_id"])
        actor = AuthenticatedDevice(target, UUID(owner["device_id"]))
        body = {
            "action": "export",
            "family_id": str(family_id),
            "target_id": str(target),
            "acl_revision": 0,
        }

        async def challenge() -> dict:
            r = await client.post("/v1/auth/step-up/options", headers=headers, json=body)
            assert r.status_code == 200, r.text
            assert r.headers["Cache-Control"] == "no-store"
            return r.json()

        def completion(c: dict, cred: str = credential) -> dict:
            return {
                "challenge_id": c["challenge_id"],
                "credential": {"id": b64(cred.encode()), "challenge": c["public_key"]["challenge"]},
            }

        async def proof() -> str:
            c = await challenge()
            r = await client.post("/v1/auth/step-up/complete", headers=headers, json=completion(c))
            assert r.status_code == 200, r.text
            assert r.headers["Cache-Control"] == "no-store"
            assert (
                await client.post("/v1/auth/step-up/complete", headers=headers, json=completion(c))
            ).status_code == 401
            return r.json()["proof"]

        assert (await client.post("/v1/auth/step-up/options", json=body)).status_code == 401
        assert (
            await client.post("/v1/auth/step-up/options", headers=api.headers(outsider), json=body)
        ).status_code == 404
        assert (
            await client.post(
                "/v1/auth/step-up/options",
                headers=headers,
                json={**body, "raw_text": "private canary"},
            )
        ).status_code == 422
        assert (
            await client.post(
                "/v1/auth/step-up/options", headers=headers, json={**body, "acl_revision": 1}
            )
        ).status_code == 409
        assert (
            await client.post(
                "/v1/auth/step-up/options",
                headers=headers,
                json={**body, "action": "account.delete"},
            )
        ).status_code == 422
        c = await challenge()
        assert (
            await client.post(
                "/v1/auth/step-up/complete",
                headers=headers,
                json=completion(c, outsider_credential),
            )
        ).status_code == 401
        assert (
            await client.post(
                "/v1/auth/step-up/complete",
                headers=api.headers(outsider),
                json=completion(c, outsider_credential),
            )
        ).status_code in (401, 404)
        invalid = completion(c)
        invalid["credential"]["challenge"] = "bad"
        assert (
            await client.post("/v1/auth/step-up/complete", headers=headers, json=invalid)
        ).status_code == 401
        invalid = completion(c)
        invalid["credential"]["id"] = "*"
        assert (
            await client.post("/v1/auth/step-up/complete", headers=headers, json=invalid)
        ).status_code == 401
        with database.transaction() as conn:
            conn.execute(
                update(sensitive_authorizations)
                .where(sensitive_authorizations.c.id == UUID(c["challenge_id"]))
                .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
            )
        assert (
            await client.post("/v1/auth/step-up/complete", headers=headers, json=completion(c))
        ).status_code == 401
        token = await proof()
        with database.connect() as conn:
            assert (
                conn.execute(
                    select(func.count()).select_from(devices).where(devices.c.adult_id == target)
                ).scalar_one()
                == 1
            )
            assert (
                conn.execute(
                    select(devices.c.id).where(
                        devices.c.adult_id == target, devices.c.state == "active"
                    )
                ).scalar_one()
                == actor.device_id
            )
            assert (
                conn.execute(
                    select(sessions.c.revoked_at).where(sessions.c.device_id == actor.device_id)
                ).scalar_one()
                is None
            )
            assert (
                conn.execute(
                    select(sensitive_authorizations.c.proof_digest).where(
                        sensitive_authorizations.c.proof_digest
                        == hashlib.sha256(token.encode()).digest()
                    )
                ).scalar_one()
                != token.encode()
            )

        def consume(**kwargs: object) -> None:
            args = {
                "request": request_for(owner["session_token"]),
                "actor": actor,
                "proof": token,
                "action": "export",
                "family_id": family_id,
                "target_id": target,
                "revision": 0,
                **kwargs,
            }
            with database.transaction() as conn:
                consume_step_up(conn, **args)

        for overrides in [
            {"action": "membership.revoke"},
            {"target_id": uuid4()},
            {"proof": "!"},
            {"proof": "é" * 43},
            {"request": request_for(outsider["session_token"])},
        ]:
            with pytest.raises(ApiError):
                consume(**overrides)

        # One success across concurrent consumers; no duplicate sensitive action.
        def attempt(_: int) -> bool:
            try:
                consume()
                return True
            except ApiError:
                return False

        with ThreadPoolExecutor(max_workers=4) as pool:
            assert sum(pool.map(attempt, range(4))) == 1
        token = await proof()
        with database.transaction() as conn:
            conn.execute(update(families).where(families.c.id == family_id).values(acl_revision=1))
        with pytest.raises(ApiError):
            consume()
        with database.transaction() as conn:
            conn.execute(update(families).where(families.c.id == family_id).values(acl_revision=0))
            conn.execute(
                update(sensitive_authorizations)
                .where(
                    sensitive_authorizations.c.proof_digest
                    == hashlib.sha256(token.encode()).digest()
                )
                .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
            )
        with pytest.raises(ApiError):
            consume()
        token = await proof()
        with database.transaction() as conn:
            conn.execute(
                update(devices)
                .where(devices.c.id == actor.device_id)
                .values(state="revoked", revoked_at=datetime.now(UTC))
            )
        with pytest.raises(ApiError):
            consume()
        assert (
            await client.post("/v1/auth/step-up/options", headers=headers, json=body)
        ).status_code == 401
    database.close()


def test_current_device_step_up_binding_replay_expiry_and_concurrency() -> None:
    asyncio.run(flow())


async def account_flow() -> None:
    database = Database(os.environ["SARTI_DATABASE_URL"])
    app = create_app(
        Settings(database_url=os.environ["SARTI_DATABASE_URL"]),
        database=database,
        webauthn=StubWebAuthn(),
    )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        owner = await api.register(str(uuid4()))
        headers = api.headers(owner)
        binding = {"action": "account.delete", "target_id": owner["adult_id"], "acl_revision": 0}
        assert (
            await client.post(
                "/v1/auth/step-up/options",
                headers=headers,
                json={**binding, "target_id": str(uuid4())},
            )
        ).status_code == 403
        for _ in range(20):
            assert (
                await client.post("/v1/auth/step-up/options", headers=headers, json=binding)
            ).status_code == 200
        assert (
            await client.post("/v1/auth/step-up/options", headers=headers, json=binding)
        ).status_code == 409
    database.close()


def test_step_up_own_account_scope_and_bounded_pending_challenges() -> None:
    asyncio.run(account_flow())
