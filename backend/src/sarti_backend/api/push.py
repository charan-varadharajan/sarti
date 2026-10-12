from typing import Annotated, Any, Protocol
from uuid import UUID

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, ConfigDict

from sarti_backend.core.auth import AuthenticatedDevice, require_device
from sarti_backend.households.authorization import require_active_member

router = APIRouter(prefix="/v1/push", tags=["push"])
Authenticated = Annotated[AuthenticatedDevice, Depends(require_device)]


class TransactionalDatabase(Protocol):
    def transaction(self) -> Any: ...

    def connect(self) -> Any: ...


class PushTokenRegister(BaseModel):
    model_config = ConfigDict(extra="forbid")

    fcm_token: str


class PushTokenResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    registered: bool


class WakeUpRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    family_id: UUID


class WakeUpResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    dispatched: int


@router.post("/register", response_model=PushTokenResponse)
def register_push_token(
    payload: PushTokenRegister,
    request: Request,
    actor: Authenticated,
) -> PushTokenResponse:
    """Store an FCM token for the authenticated device."""
    from sarti_backend.db.schema import devices

    database: TransactionalDatabase = request.app.state.database
    from sqlalchemy import update

    with database.transaction() as connection:
        connection.execute(
            update(devices)
            .where(devices.c.id == actor.device_id)
            .values(fcm_token=payload.fcm_token)
        )
    return PushTokenResponse(registered=True)


@router.post("/wake-up", response_model=WakeUpResponse)
def send_wake_up(
    payload: WakeUpRequest,
    request: Request,
    actor: Authenticated,
) -> WakeUpResponse:
    """Send an opaque sync_available wake-up to all other active family devices.

    Payload sent to FCM: {"type": "sync_available"} only.
    No event titles, child names, family identifiers, or any family content
    are included (ADR-026).
    """
    from sqlalchemy import and_, select

    from sarti_backend.db.schema import devices, memberships

    database: TransactionalDatabase = request.app.state.database
    fcm_credentials_file = request.app.state.settings.fcm_credentials_file

    with database.connect() as connection:
        require_active_member(connection, payload.family_id, actor.adult_id)

        # Collect FCM tokens for all other active devices in this family
        rows = (
            connection.execute(
                select(devices.c.fcm_token)
                .join(memberships, memberships.c.adult_id == devices.c.adult_id)
                .where(
                    and_(
                        memberships.c.family_id == payload.family_id,
                        memberships.c.status == "active",
                        devices.c.state == "active",
                        devices.c.id != actor.device_id,
                        devices.c.fcm_token.isnot(None),
                    )
                )
            )
            .scalars()
            .all()
        )

    tokens = [t for t in rows if t]
    if not tokens or not fcm_credentials_file:
        return WakeUpResponse(dispatched=0)

    dispatched = _send_fcm(fcm_credentials_file, tokens)
    return WakeUpResponse(dispatched=dispatched)


def _send_fcm(credentials_file: str, tokens: list[str]) -> int:
    """Send opaque wake-up via FCM. Returns number of tokens dispatched to."""
    try:
        import firebase_admin  # type: ignore[import-untyped]
        from firebase_admin import credentials, messaging

        if not firebase_admin._apps:
            cred = credentials.Certificate(credentials_file)
            firebase_admin.initialize_app(cred)

        # Opaque payload only — no family content (ADR-026)
        messages = [
            messaging.Message(
                data={"type": "sync_available"},
                token=token,
                android=messaging.AndroidConfig(priority="normal"),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(aps=messaging.Aps(content_available=True))
                ),
            )
            for token in tokens
        ]
        response = messaging.send_each(messages)
        return sum(1 for r in response.responses if r.success)
    except Exception:
        return 0
