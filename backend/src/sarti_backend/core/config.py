from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="SARTI_",
        case_sensitive=False,
        extra="ignore",
    )

    environment: Literal["development", "test", "production"] = "development"
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"
    database_url: str = Field(min_length=1, repr=False)
    webauthn_rp_id: str = Field(default="localhost", min_length=1)
    webauthn_origin: str = Field(default="http://localhost:8000", min_length=1)
    email_worker_secret: str = Field(default="", repr=False)
    gemini_api_key: str = Field(default="", repr=False)
    cloud_ai_enabled: bool = False
    cloud_ai_reviewed: bool = False
    cloud_ai_model: Literal["", "gemini-2.5-flash-lite"] = ""
    fcm_credentials_file: str = Field(default="")


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
