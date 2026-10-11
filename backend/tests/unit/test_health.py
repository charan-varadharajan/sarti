import asyncio
from uuid import UUID

from httpx import ASGITransport, AsyncClient, Response

from sarti_backend.core.config import Settings
from sarti_backend.main import create_app


class StubDatabase:
    def __init__(self, ready: bool) -> None:
        self.ready = ready
        self.closed = False

    def is_ready(self) -> bool:
        return self.ready

    def close(self) -> None:
        self.closed = True


def test_liveness_contract() -> None:
    app = create_app(
        Settings(environment="test", database_url="postgresql+psycopg://unused"),
        StubDatabase(ready=True),
    )

    async def request() -> Response:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            return await client.get(
                "/v1/health/live",
                headers={"X-Request-ID": "00000000-0000-4000-8000-000000000003"},
            )

    response = asyncio.run(request())

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert response.headers["X-Request-ID"] == "00000000-0000-4000-8000-000000000003"


def test_readiness_fails_closed() -> None:
    app = create_app(
        Settings(environment="test", database_url="postgresql+psycopg://unused"),
        StubDatabase(ready=False),
    )

    async def request() -> Response:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            return await client.get("/v1/health/ready")

    response = asyncio.run(request())

    assert response.status_code == 503
    assert response.json() == {"status": "unavailable"}


def test_untrusted_request_id_is_not_reflected() -> None:
    app = create_app(
        Settings(environment="test", database_url="postgresql+psycopg://unused"),
        StubDatabase(ready=True),
    )

    async def request() -> Response:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            return await client.get(
                "/v1/health/live",
                headers={"X-Request-ID": "private-family-data"},
            )

    response = asyncio.run(request())

    assert response.headers["X-Request-ID"] != "private-family-data"
    UUID(response.headers["X-Request-ID"])
