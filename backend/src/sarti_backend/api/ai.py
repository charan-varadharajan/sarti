from datetime import UTC, datetime
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request, Response

from sarti_backend.ai.broker import (
    ProposalRequest,
    ProposalResponse,
    generate_proposal,
    reserve_attempt,
)
from sarti_backend.core.auth import AuthenticatedDevice, require_device
from sarti_backend.core.errors import ApiError

router = APIRouter(prefix="/v1/ai", tags=["ai"])
Authenticated = Annotated[AuthenticatedDevice, Depends(require_device)]


@router.get("/capability")
def capability(request: Request, response: Response, actor: Authenticated) -> dict[str, Any]:
    response.headers["Cache-Control"] = "no-store"
    settings = request.app.state.settings
    return {
        "available": settings.cloud_ai_enabled
        and settings.cloud_ai_reviewed
        and bool(settings.gemini_api_key)
        and bool(settings.cloud_ai_model),
        "consent_version": 3,
    }


@router.post("/proposals", response_model=ProposalResponse, response_model_exclude_none=True)
async def propose(
    payload: ProposalRequest, request: Request, response: Response, actor: Authenticated
) -> dict[str, Any]:
    response.headers["Cache-Control"] = "no-store"
    settings = request.app.state.settings
    if not (
        settings.cloud_ai_enabled
        and settings.cloud_ai_reviewed
        and settings.gemini_api_key
        and settings.cloud_ai_model
    ):
        raise ApiError("cloud_disabled", "Cloud assist is disabled. Continue locally.", 503)
    with request.app.state.database.transaction() as connection:
        reserve_attempt(connection, actor.adult_id, datetime.now(UTC))
    return await generate_proposal(
        payload.tokens, key=settings.gemini_api_key, model=settings.cloud_ai_model
    )
