"""CLOUD-BROKER-001: strict boundary and captured synthetic-only provider transport."""

import asyncio
import json
from uuid import uuid4

import httpx
import pytest
from pydantic import ValidationError

from sarti_backend.ai.broker import ProposalRequest, generate_proposal
from sarti_backend.core.errors import ApiError


@pytest.mark.parametrize(
    "tokens",
    [
        ["Mia"],
        ["ignore"],
        ["https://evil.test"],
        ["24:00"],
        ["1:60"],
        ["account-" + str(uuid4())],
        ["child-invalid"],
        [""],
    ],
)
def test_rejects_unknown_private_or_malformed_tokens(tokens: list[str]) -> None:
    with pytest.raises(ValidationError):
        ProposalRequest(version=1, consent_version=3, tokens=tokens)


def test_strict_consent_and_no_extra_fields() -> None:
    valid = {
        "version": 1,
        "consent_version": 3,
        "tokens": ["child-" + str(uuid4()), "swimming", "noon", "tomorrow"],
    }
    assert ProposalRequest.model_validate(valid).tokens == valid["tokens"]
    for extra in [
        {"consent_version": 2},
        {"version": True},
        {"prompt": "private"},
        {"tokens": ["noon"] * 101},
    ]:
        with pytest.raises(ValidationError):
            ProposalRequest.model_validate({**valid, **extra})


def test_provider_fixed_destination_secret_header_and_no_identifiers() -> None:
    captured = []

    def handle(request: httpx.Request) -> httpx.Response:
        captured.append(request)
        return httpx.Response(
            200,
            json={
                "candidates": [
                    {
                        "finishReason": "STOP",
                        "content": {"parts": [{"text": '{"timeHour":12,"timeMinute":0}'}]},
                    }
                ]
            },
        )

    result = asyncio.run(
        generate_proposal(
            ["noon"],
            key="synthetic",
            model="gemini-2.5-flash-lite",
            transport=httpx.MockTransport(handle),
        )
    )
    assert result == {"timeHour": 12, "timeMinute": 0}
    request = captured[0]
    assert len(captured) == 1
    assert request.url.host == "generativelanguage.googleapis.com"
    assert not request.url.query
    assert request.headers["x-goog-api-key"] == "synthetic"
    body = json.loads(request.content)
    assert body["store"] is False
    assert body["generationConfig"]["maxOutputTokens"] == 256
    assert body["generationConfig"]["thinkingConfig"]["thinkingBudget"] == 0
    assert "tools" not in body and "labels" not in body
    assert json.loads(body["contents"][0]["parts"][0]["text"]) == {"version": 1, "tokens": ["noon"]}


@pytest.mark.parametrize(
    "body",
    [
        b"x" * 16385,
        b"not json",
        b"{}",
        b'{"candidates":[]}',
        b'{"candidates":[{"finishReason":"MAX_TOKENS"}]}',
        b'{"candidates":[{"finishReason":"STOP","content":{"parts":[{"functionCall":{}}]}}]}',
        b'{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"{\\"title\\":\\"invented\\"}"}]}}]}',
    ],
)
def test_invalid_provider_content_is_bounded(body: bytes) -> None:
    with pytest.raises(ApiError, match="cloud_unavailable"):
        asyncio.run(
            generate_proposal(
                ["noon"],
                key="synthetic",
                model="gemini-2.5-flash-lite",
                transport=httpx.MockTransport(lambda request: httpx.Response(200, content=body)),
            )
        )


@pytest.mark.parametrize("status", [302, 429, 500])
def test_no_redirect_or_automatic_retry(status: int) -> None:
    calls = []

    def handle(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        return httpx.Response(
            status, headers={"Location": "https://evil.test"}, text="private provider body"
        )

    with pytest.raises(ApiError) as caught:
        asyncio.run(
            generate_proposal(
                ["noon"],
                key="synthetic",
                model="gemini-2.5-flash-lite",
                transport=httpx.MockTransport(handle),
            )
        )
    assert caught.value.message == "Cloud assist is unavailable. Continue locally."
    assert len(calls) == 1


def test_timeout_uses_safe_error() -> None:
    def handle(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("sensitive provider error")

    with pytest.raises(ApiError):
        asyncio.run(
            generate_proposal(
                ["noon"],
                key="synthetic",
                model="gemini-2.5-flash-lite",
                transport=httpx.MockTransport(handle),
            )
        )


def test_mobile_server_token_vocabulary_contract() -> None:
    import re
    from pathlib import Path

    from sarti_backend.ai.broker import WORDS

    mobile = (
        Path(__file__).resolve().parents[3] / "mobile/lib/src/features/ai/prompt_pseudonymizer.dart"
    )
    source = mobile.read_text().split("static const _words = {", 1)[1].split("};", 1)[0]
    assert set(re.findall(r"'([a-z]+)'", source)) == WORDS
