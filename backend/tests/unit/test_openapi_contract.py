import json
from pathlib import Path

from sarti_backend.core.config import Settings
from sarti_backend.main import create_app


class StubDatabase:
    def is_ready(self) -> bool:
        return True

    def close(self) -> None:
        return None


def test_generated_openapi_matches_committed_contract() -> None:
    app = create_app(
        Settings(environment="test", database_url="postgresql+psycopg://unused"),
        StubDatabase(),
    )
    expected_path = Path(__file__).parents[2] / "openapi.json"
    expected = json.loads(expected_path.read_text(encoding="utf-8"))

    assert app.openapi() == expected
