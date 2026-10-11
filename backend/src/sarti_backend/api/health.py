from typing import Literal, Protocol

from fastapi import APIRouter, Request, Response, status
from pydantic import BaseModel, ConfigDict


class ReadinessCheck(Protocol):
    def is_ready(self) -> bool: ...


class HealthResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["ok", "ready", "unavailable"]


router = APIRouter(prefix="/v1/health", tags=["health"])


@router.get(
    "/live",
    operation_id="health_live",
    response_model=HealthResponse,
    summary="Check whether the API process is alive",
)
def live() -> HealthResponse:
    return HealthResponse(status="ok")


@router.get(
    "/ready",
    operation_id="health_ready",
    response_model=HealthResponse,
    responses={503: {"model": HealthResponse, "description": "PostgreSQL is unavailable."}},
    summary="Check whether the API and PostgreSQL are ready",
)
def ready(request: Request, response: Response) -> HealthResponse:
    database: ReadinessCheck = request.app.state.database
    if not database.is_ready():
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return HealthResponse(status="unavailable")
    return HealthResponse(status="ready")
