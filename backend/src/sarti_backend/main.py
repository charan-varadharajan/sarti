import logging
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any, Protocol
from uuid import UUID, uuid4

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from sarti_backend.api.health import router as health_router
from sarti_backend.core.config import Settings, get_settings
from sarti_backend.core.errors import ApiError
from sarti_backend.core.logging import configure_logging
from sarti_backend.db.database import Database

logger = logging.getLogger("sarti.http")


class DatabaseHandle(Protocol):
    def is_ready(self) -> bool: ...

    def close(self) -> None: ...


def _request_id(request: Request) -> str:
    candidate = request.headers.get("X-Request-ID", "")
    try:
        return str(UUID(candidate))
    except ValueError:
        return str(uuid4())


def _error_response(code: str, message: str, request_id: str, status_code: int) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={"error": {"code": code, "message": message, "request_id": request_id}},
        headers={"X-Request-ID": request_id},
    )


def create_app(settings: Settings | None = None, database: DatabaseHandle | None = None) -> FastAPI:
    resolved_settings = settings or get_settings()
    configure_logging(resolved_settings.log_level)
    resolved_database = database or Database(resolved_settings.database_url)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        yield
        resolved_database.close()

    app = FastAPI(
        title="Sarti API",
        version="0.1.0",
        description="Operational API for the Sarti privacy-first family organizer.",
        docs_url=None,
        lifespan=lifespan,
        openapi_url=None,
        redoc_url=None,
    )
    app.state.database = resolved_database

    @app.middleware("http")
    async def request_context(request: Request, call_next: Any) -> Any:
        request_id = _request_id(request)
        request.state.request_id = request_id
        started = time.monotonic()
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        logger.info(
            "request_complete",
            extra={
                "duration_ms": round((time.monotonic() - started) * 1000, 2),
                "event": "request_complete",
                "method": request.method,
                "request_id": request_id,
                "status_code": response.status_code,
            },
        )
        return response

    @app.exception_handler(ApiError)
    async def handle_api_error(request: Request, error: ApiError) -> JSONResponse:
        return _error_response(
            error.code,
            error.message,
            request.state.request_id,
            error.status_code,
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(request: Request, _: RequestValidationError) -> JSONResponse:
        return _error_response(
            "validation_error",
            "The request is invalid.",
            request.state.request_id,
            status.HTTP_422_UNPROCESSABLE_CONTENT,
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(request: Request, error: Exception) -> JSONResponse:
        request_id = request.state.request_id
        logger.error(
            "request_failed",
            extra={
                "error_type": type(error).__name__,
                "event": "request_failed",
                "request_id": request_id,
            },
        )
        return _error_response(
            "internal_error",
            "The request could not be completed.",
            request_id,
            status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    app.include_router(health_router)
    return app


app = create_app()
