from sqlalchemy.ext.asyncio import AsyncSession

from app.core.enums import Severity
from app.services.alerting.config_repo import ConfigRepository
from app.services.alerting.persistence import PersistenceThresholds


async def get_persistence_thresholds(
    config_repo: ConfigRepository,
    severity: Severity,
    direction: str,
) -> PersistenceThresholds:
    """
    Load persistence thresholds for a severity transition.

    Example keys:

        persistence.WARNING.escalate.min_duration_sec
        persistence.WARNING.escalate.min_confirmations

    The ConfigRepository automatically falls back to DEFAULT_CONFIG
    when the values are not explicitly stored in alert_config.
    """

    severity_name = severity.value

    duration_key = (
        f"persistence.{severity_name}.{direction}.min_duration_sec"
    )

    confirmations_key = (
        f"persistence.{severity_name}.{direction}.min_confirmations"
    )

    duration_value = await config_repo.get(duration_key)
    confirmations_value = await config_repo.get(confirmations_key)

    min_duration_sec = (
        int(duration_value)
        if duration_value is not None
        else None
    )

    min_confirmations = (
        int(confirmations_value)
        if confirmations_value is not None
        else None
    )

    return PersistenceThresholds(
        min_duration_sec=min_duration_sec,
        min_confirmations=min_confirmations,
    )

async def get_notify_on_downgrade(
    config_repo: ConfigRepository,
) -> bool:
    value = await config_repo.get(
        "notify_on_downgrade",
        default="false",
    )

    return str(value).strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }

class ConfigService:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.repository = ConfigRepository(session)

    async def get(
        self,
        key: str,
        default: str | None = None,
    ) -> str | None:
        return await self.repository.get(
            key,
            default=default,
        )

    async def get_int(
        self,
        key: str,
        default: int = 0,
    ) -> int:
        return await self.repository.get_int(
            key,
            default=default,
        )

    async def get_bool(
        self,
        key: str,
        default: bool = False,
    ) -> bool:
        return await self.repository.get_bool(
            key,
            default=default,
        )

    async def set(
        self,
        key: str,
        value: str,
        updated_by: str | None = None,
    ) -> None:
        await self.repository.set(
            key,
            value,
            updated_by=updated_by,
        )