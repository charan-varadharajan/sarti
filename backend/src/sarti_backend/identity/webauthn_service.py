from dataclasses import dataclass
from typing import Any, Protocol

from webauthn import (
    generate_authentication_options,
    generate_registration_options,
    verify_authentication_response,
    verify_registration_response,
)
from webauthn.helpers import options_to_json_dict
from webauthn.helpers.structs import (
    AuthenticatorSelectionCriteria,
    ResidentKeyRequirement,
    UserVerificationRequirement,
)


@dataclass(frozen=True, slots=True)
class VerifiedRegistration:
    credential_id: bytes
    credential_public_key: bytes
    sign_count: int


@dataclass(frozen=True, slots=True)
class VerifiedAuthentication:
    new_sign_count: int


class WebAuthnVerifier(Protocol):
    def registration_options(
        self, *, challenge: bytes, user_id: bytes, user_name: str
    ) -> dict[str, Any]: ...

    def verify_registration(
        self, *, credential: dict[str, Any], challenge: bytes
    ) -> VerifiedRegistration: ...

    def authentication_options(self, *, challenge: bytes) -> dict[str, Any]: ...

    def verify_authentication(
        self,
        *,
        credential: dict[str, Any],
        challenge: bytes,
        credential_public_key: bytes,
        current_sign_count: int,
    ) -> VerifiedAuthentication: ...


class StandardWebAuthnVerifier:
    def __init__(self, rp_id: str, origin: str) -> None:
        self._rp_id = rp_id
        self._origin = origin

    def registration_options(
        self, *, challenge: bytes, user_id: bytes, user_name: str
    ) -> dict[str, Any]:
        options = generate_registration_options(
            rp_id=self._rp_id,
            rp_name="Sarti",
            user_id=user_id,
            user_name=user_name,
            user_display_name="Sarti parent",
            challenge=challenge,
            authenticator_selection=AuthenticatorSelectionCriteria(
                resident_key=ResidentKeyRequirement.REQUIRED,
                user_verification=UserVerificationRequirement.REQUIRED,
            ),
        )
        return options_to_json_dict(options)

    def verify_registration(
        self, *, credential: dict[str, Any], challenge: bytes
    ) -> VerifiedRegistration:
        result = verify_registration_response(
            credential=credential,
            expected_challenge=challenge,
            expected_rp_id=self._rp_id,
            expected_origin=self._origin,
            require_user_verification=True,
        )
        return VerifiedRegistration(
            credential_id=result.credential_id,
            credential_public_key=result.credential_public_key,
            sign_count=result.sign_count,
        )

    def authentication_options(self, *, challenge: bytes) -> dict[str, Any]:
        options = generate_authentication_options(
            rp_id=self._rp_id,
            challenge=challenge,
            user_verification=UserVerificationRequirement.REQUIRED,
        )
        return options_to_json_dict(options)

    def verify_authentication(
        self,
        *,
        credential: dict[str, Any],
        challenge: bytes,
        credential_public_key: bytes,
        current_sign_count: int,
    ) -> VerifiedAuthentication:
        result = verify_authentication_response(
            credential=credential,
            expected_challenge=challenge,
            expected_rp_id=self._rp_id,
            expected_origin=self._origin,
            credential_public_key=credential_public_key,
            credential_current_sign_count=current_sign_count,
            require_user_verification=True,
        )
        return VerifiedAuthentication(new_sign_count=result.new_sign_count)
