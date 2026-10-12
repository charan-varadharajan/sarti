"""Unit tests for email ingest and push notification endpoints."""

import asyncio
import hashlib
import json
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from typing import Any
from unittest.mock import MagicMock, patch
from uuid import UUID, uuid4

from httpx import ASGITransport, AsyncClient
from nacl.public import PrivateKey, SealedBox

from sarti_backend.core.config import Settings
from sarti_backend.main import create_app

_WORKER_SECRET = "test-worker-secret-abc123"
_FAMILY_TOKEN = "family-token-xyz-9876"
_FAMILY_TOKEN_DIGEST = hashlib.sha256(_FAMILY_TOKEN.encode()).digest()
_FAMILY_ID = UUID("00000000-0000-4000-8000-000000000010")
_DEVICE_ID = UUID("00000000-0000-4000-8000-000000000020")
_ADULT_ID = UUID("00000000-0000-4000-8000-000000000030")
_DEVICE_PRIVATE_KEY = PrivateKey.generate()


def _settings(**overrides: Any) -> Settings:
    base = {
        "environment": "test",
        "database_url": "postgresql+psycopg://unused",
        "email_worker_secret": _WORKER_SECRET,
    }
    base.update(overrides)
    return Settings(**base)  # type: ignore[arg-type]


class StubDatabase:
    """Test double for Database. Exposes .conn so tests can configure it."""

    def __init__(self, ready: bool = True) -> None:
        self.ready = ready
        self.closed = False
        self.conn: MagicMock = MagicMock()

    def is_ready(self) -> bool:
        return self.ready

    def close(self) -> None:
        self.closed = True

    def transaction(self) -> "StubDatabase":
        return self

    def connect(self) -> "StubDatabase":
        return self

    def __enter__(self) -> MagicMock:
        return self.conn

    def __exit__(self, *_: Any) -> None:
        pass


def _make_family_row(family_id: UUID = _FAMILY_ID) -> dict[str, Any]:
    return {"id": family_id, "email_token_digest": _FAMILY_TOKEN_DIGEST}


def _run(coro: Any) -> Any:
    return asyncio.run(coro)


def _make_conn(family_row: Any, rate_count: int = 0, duplicate_row: Any = None) -> MagicMock:
    """Connection mock with per-call execute side effects."""
    conn = MagicMock()

    family_result = MagicMock()
    family_result.mappings.return_value.one_or_none.return_value = family_row

    rate_result = MagicMock()
    rate_result.scalar_one.return_value = rate_count

    dup_result = MagicMock()
    dup_result.mappings.return_value.one_or_none.return_value = duplicate_row

    recipients_result = MagicMock()
    recipients_result.all.return_value = [
        SimpleNamespace(
            id=_DEVICE_ID,
            encryption_public_key=bytes(_DEVICE_PRIVATE_KEY.public_key),
        )
    ]

    conn.execute.side_effect = [
        MagicMock(),  # expired-row cleanup
        family_result,
        rate_result,
        dup_result,
        recipients_result,
        MagicMock(),  # suggestion metadata insert
        MagicMock(),  # per-device ciphertext insert
    ]
    return conn


# ---------------------------------------------------------------------------
# Email ingest tests
# ---------------------------------------------------------------------------


def _post_email(app: Any, payload: dict[str, Any], secret: str = _WORKER_SECRET) -> Any:
    async def _req() -> Any:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            return await c.post(
                "/v1/email/ingest",
                json=payload,
                headers={"X-Worker-Secret": secret},
            )

    return _run(_req())


def test_email_ingest_missing_secret_returns_403() -> None:
    db = StubDatabase()
    app = create_app(_settings(), db)

    async def _req() -> Any:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            return await c.post(
                "/v1/email/ingest",
                json={"family_token": _FAMILY_TOKEN, "sender": "a@b.com"},
            )

    assert _run(_req()).status_code == 403


def test_email_ingest_wrong_secret_returns_403() -> None:
    db = StubDatabase()
    app = create_app(_settings(), db)
    r = _post_email(
        app,
        {"family_token": _FAMILY_TOKEN, "sender": "a@b.com"},
        secret="wrong",  # noqa: S106 - deliberate invalid test credential
    )
    assert r.status_code == 403


def test_email_ingest_unknown_family_token_returns_404() -> None:
    db = StubDatabase()
    app = create_app(_settings(), db)

    family_result = MagicMock()
    family_result.mappings.return_value.one_or_none.return_value = None
    db.conn.execute.side_effect = [MagicMock(), family_result]

    r = _post_email(app, {"family_token": "unknown-token-xyz-9999", "sender": "a@b.com"})
    assert r.status_code == 404


def test_email_ingest_stores_suggestion_and_returns_201() -> None:
    db = StubDatabase()
    app = create_app(_settings(), db)
    db.conn = _make_conn(family_row=_make_family_row(), rate_count=0, duplicate_row=None)

    r = _post_email(
        app,
        {"family_token": _FAMILY_TOKEN, "sender": "school@example.com", "subject": "Trip"},
    )
    assert r.status_code == 201
    body = r.json()
    assert "suggestion_id" in body
    assert "expires_at" in body


def test_email_ingest_deduplicates_identical_content() -> None:
    db = StubDatabase()
    app = create_app(_settings(), db)

    existing_id = uuid4()
    existing_expires = datetime.now(UTC) + timedelta(days=5)
    db.conn = _make_conn(
        family_row=_make_family_row(),
        rate_count=0,
        duplicate_row={"id": existing_id, "expires_at": existing_expires},
    )

    r = _post_email(
        app,
        {"family_token": _FAMILY_TOKEN, "sender": "school@example.com", "subject": "Trip"},
    )
    assert r.status_code == 201
    assert r.json()["suggestion_id"] == str(existing_id)


def test_email_ingest_strips_injection_pattern() -> None:
    """<INPUT> tags in body/subject must be stripped before storage."""
    db = StubDatabase()
    app = create_app(_settings(), db)
    db.conn = _make_conn(family_row=_make_family_row(), rate_count=0, duplicate_row=None)

    r = _post_email(
        app,
        {
            "family_token": _FAMILY_TOKEN,
            "sender": "a@b.com",
            "subject": "<INPUT>inject</INPUT>",
            "body": "Hello <INPUT>bad</INPUT> world",
        },
    )
    assert r.status_code == 201
    delivery_values = db.conn.execute.call_args_list[-1].args[1]
    plaintext = SealedBox(_DEVICE_PRIVATE_KEY).decrypt(delivery_values[0]["ciphertext"])
    delivered = json.loads(plaintext)
    assert delivered["subject"] == "inject"
    assert delivered["body"] == "Hello bad world"
    assert "sender" not in str(db.conn.execute.call_args_list[-2].args[0].compile().params)


def test_email_suggestions_require_device_and_return_only_ciphertext() -> None:
    from sarti_backend.core.auth import AuthenticatedDevice, require_device

    db = StubDatabase()
    app = create_app(_settings(), db)
    actor = AuthenticatedDevice(adult_id=_ADULT_ID, device_id=_DEVICE_ID)
    app.dependency_overrides[require_device] = lambda: actor
    suggestion_id = uuid4()
    now = datetime.now(UTC)
    rows = MagicMock()
    rows.all.return_value = [
        SimpleNamespace(
            id=suggestion_id,
            ciphertext=b"sealed-only",
            received_at=now,
            expires_at=now + timedelta(days=7),
        )
    ]
    db.conn.execute.side_effect = [MagicMock(), rows]

    async def _req() -> Any:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            return await c.get("/v1/email/suggestions", headers={"Authorization": "Bearer fake"})

    response = _run(_req())
    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()[0]["suggestion_id"] == str(suggestion_id)
    assert set(response.json()[0]) == {
        "suggestion_id",
        "ciphertext",
        "received_at",
        "expires_at",
    }


def test_email_suggestion_dismissal_is_scoped_to_authenticated_device() -> None:
    from sarti_backend.core.auth import AuthenticatedDevice, require_device

    db = StubDatabase()
    app = create_app(_settings(), db)
    app.dependency_overrides[require_device] = lambda: AuthenticatedDevice(
        adult_id=_ADULT_ID, device_id=_DEVICE_ID
    )
    result = MagicMock(rowcount=1)
    db.conn.execute.return_value = result

    async def _req() -> Any:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            return await c.delete(
                f"/v1/email/suggestions/{uuid4()}",
                headers={"Authorization": "Bearer fake"},
            )

    response = _run(_req())
    app.dependency_overrides.clear()

    assert response.status_code == 204
    compiled = db.conn.execute.call_args.args[0].compile()
    assert _DEVICE_ID in compiled.params.values()


# ---------------------------------------------------------------------------
# Push endpoint tests
# ---------------------------------------------------------------------------


def test_push_register_unauthenticated_returns_401() -> None:
    db = StubDatabase()
    app = create_app(_settings(), db)

    async def _req() -> Any:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            return await c.post("/v1/push/register", json={"fcm_token": "tok"})

    assert _run(_req()).status_code == 401


def test_push_wakeup_unauthenticated_returns_401() -> None:
    db = StubDatabase()
    app = create_app(_settings(), db)

    async def _req() -> Any:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            return await c.post("/v1/push/wake-up", json={"family_id": str(_FAMILY_ID)})

    assert _run(_req()).status_code == 401


def test_push_wakeup_no_fcm_credentials_returns_zero_dispatched() -> None:
    """When fcm_credentials_file is empty, dispatched=0 without error."""
    from sarti_backend.core.auth import AuthenticatedDevice, require_device

    db = StubDatabase()
    app = create_app(_settings(fcm_credentials_file=""), db)

    db.conn.execute.return_value.scalars.return_value.all.return_value = ["fcm-token-abc"]

    actor = AuthenticatedDevice(adult_id=_ADULT_ID, device_id=_DEVICE_ID)
    app.dependency_overrides[require_device] = lambda: actor

    with patch("sarti_backend.households.authorization.require_active_member"):

        async def _req() -> Any:
            async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
                return await c.post(
                    "/v1/push/wake-up",
                    json={"family_id": str(_FAMILY_ID)},
                    headers={"Authorization": "Bearer fake"},
                )

        r = _run(_req())

    app.dependency_overrides.clear()
    assert r.status_code == 200
    assert r.json()["dispatched"] == 0
