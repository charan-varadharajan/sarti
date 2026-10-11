import asyncio

import pytest
from httpx import ASGITransport, AsyncClient, Response

from sarti_backend.core.config import Settings
from sarti_backend.main import create_app


class StubDatabase:
    def is_ready(self) -> bool:
        return True

    def close(self) -> None:
        return None


def test_unexpected_error_hides_message_from_response_and_log(
    capsys: pytest.CaptureFixture[str],
) -> None:
    app = create_app(
        Settings(environment="test", database_url="postgresql+psycopg://unused"),
        StubDatabase(),
    )

    @app.get("/test-only/error")
    def fail() -> None:
        raise RuntimeError("sensitive-canary")

    async def request() -> Response:
        transport = ASGITransport(app=app, raise_app_exceptions=False)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.get("/test-only/error")

    response = asyncio.run(request())
    captured = capsys.readouterr()

    assert response.status_code == 500
    assert response.json()["error"]["code"] == "internal_error"
    assert "sensitive-canary" not in response.text
    assert "sensitive-canary" not in captured.err
    assert '"error_type":"RuntimeError"' in captured.err
