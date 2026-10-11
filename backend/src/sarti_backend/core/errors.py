from dataclasses import dataclass


@dataclass(slots=True)
class ApiError(Exception):
    code: str
    message: str
    status_code: int


class TenantAccessDenied(ApiError):
    def __init__(self) -> None:
        super().__init__(
            code="resource_not_found",
            message="The requested resource was not found.",
            status_code=404,
        )


class AuthenticationRequired(ApiError):
    def __init__(self) -> None:
        super().__init__("authentication_required", "Authentication is required.", 401)


class PermissionDenied(ApiError):
    def __init__(self) -> None:
        super().__init__("permission_denied", "This action is not permitted.", 403)


class ConflictDetected(ApiError):
    def __init__(self, message: str = "The request conflicts with current state.") -> None:
        super().__init__("conflict", message, 409)


class InvalidCredential(ApiError):
    def __init__(self) -> None:
        super().__init__("invalid_credential", "The credential could not be verified.", 401)


class InvalidRequest(ApiError):
    def __init__(self, message: str = "The request is invalid.") -> None:
        super().__init__("validation_error", message, 422)
