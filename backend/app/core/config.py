"""
app/core/config.py

What this file does:
    - Reads ALL configuration from environment variables (.env file)
    - Uses Pydantic Settings so every value is type-checked at startup
    - If a required variable is missing, the app crashes immediately
      with a clear error — better than a mysterious error later.

Why we need this:
    - We NEVER hard-code passwords, secrets, or DB credentials in code.
    - This file is the single source of truth for all config values.
    - The same code works in development, staging, and production
      by just changing the .env file.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    """
    All application settings loaded from environment variables.
    
    Pydantic automatically reads from:
      1. Environment variables (OS level)
      2. .env file (if python-dotenv is installed)
    
    Types are enforced. If DATABASE_URL is missing → startup error immediately.
    """
    
    # ---- Application ----
    APP_NAME: str = "SIH Landslide Backend"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    ENVIRONMENT: str = "development"

    # ---- API ----
    API_V1_PREFIX: str = "/api/v1"

    # ---- Security ----
    SECRET_KEY: str                             # REQUIRED — no default
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    # ---- Database ----
    DATABASE_URL: str                           # REQUIRED — no default

    # ---- CORS ----
    ALLOWED_ORIGINS: str = "http://localhost:3000"

    @property
    def allowed_origins_list(self) -> list[str]:
        """Convert comma-separated origins string to a Python list."""
        return [origin.strip() for origin in self.ALLOWED_ORIGINS.split(",")]

    # ---- File Storage ----
    CLOUDINARY_CLOUD_NAME: str = "placeholder"
    CLOUDINARY_API_KEY: str = "placeholder"
    CLOUDINARY_API_SECRET: str = "placeholder"

    # Tell Pydantic Settings: read from .env file
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
    )


@lru_cache()
def get_settings() -> Settings:
    """
    Returns a cached singleton Settings instance.
    
    @lru_cache means the .env file is only read ONCE at startup,
    not on every request. This is efficient and safe.
    
    Usage anywhere in the app:
        from app.core.config import get_settings
        settings = get_settings()
        print(settings.APP_NAME)
    """
    return Settings()
