from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    All application settings loaded from environment variables
    and the .env file.
    """

    # ---- Application ----
    APP_NAME: str = "SIH Landslide Backend"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    ENVIRONMENT: str = "development"

    # ---- API ----
    API_V1_PREFIX: str = "/api/v1"

    # ---- Security ----
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    # ---- Database ----
    DATABASE_URL: str

    # ---- CORS ----
    ALLOWED_ORIGINS: str = "http://localhost:3000"

    @property
    def allowed_origins_list(self) -> list[str]:
        """Convert comma-separated origins string to a Python list."""
        return [
            origin.strip()
            for origin in self.ALLOWED_ORIGINS.split(",")
        ]

    # ---- File Storage ----
    CLOUDINARY_CLOUD_NAME: str = "placeholder"
    CLOUDINARY_API_KEY: str = "placeholder"
    CLOUDINARY_API_SECRET: str = "placeholder"

    # ---- M5 Notification Providers ----
    FCM_SERVER_KEY: str = ""

    TWILIO_ACCOUNT_SID: str = ""
    TWILIO_AUTH_TOKEN: str = ""
    TWILIO_FROM_NUMBER: str = ""

    # ---- M5 Alert Dispatcher ----
    ENABLE_DISPATCHER: bool = True
    DISPATCH_LOOP_INTERVAL_SECONDS: int = 5

    # ---- M3 Integration ----
    M3_BASE_URL: str = "http://127.0.0.1:8000"
    M3_HTTP_TIMEOUT_SECONDS: int = 10

    # ---- Internal Service Authentication ----
    M5_SERVICE_KEY: str = ""
    M3_SERVICE_KEY: str = ""

    # ---- Environment file ----
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
    )


@lru_cache()
def get_settings() -> Settings:
    """
    Returns a cached singleton Settings instance.
    """
    return Settings()