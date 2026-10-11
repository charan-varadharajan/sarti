from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
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
