"""Shared bounded relay envelope contract; no I/O or private-key handling."""

import base64
import binascii
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from sarti_backend.core.errors import InvalidRequest


def _decode(value: str, expected_size: int | None = None) -> bytes:
    try:
        result = base64.b64decode(value + "=" * (-len(value) % 4), altchars=b"-_", validate=True)
    except (ValueError, binascii.Error) as error:
        raise InvalidRequest from error
    if expected_size is not None and len(result) != expected_size:
        raise InvalidRequest
    return result


def _encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


class OperationUpload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocol_version: Literal[1, 2] = 1
    operation_id: UUID
    family_id: UUID
    resource_id: UUID
    device_sequence: int = Field(gt=0, le=2**63 - 1)
    key_epoch: int = Field(gt=0, le=2**31 - 1)
    logical_version: dict[str, int]
    nonce: str = Field(min_length=32, max_length=32)
    ciphertext: str = Field(min_length=23, max_length=1_398_124)
    content_digest: str = Field(min_length=43, max_length=44)

    @field_validator("logical_version")
    @classmethod
    def validate_version(cls, value: dict[str, int]) -> dict[str, int]:
        if not value or len(value) > 16:
            raise ValueError("logical version must contain 1-16 devices")
        for key, counter in value.items():
            UUID(key)
            if counter < 0 or counter > 2**63 - 1:
                raise ValueError("invalid logical version counter")
        return value
