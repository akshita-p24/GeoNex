from typing import Optional

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.constants import DEFAULT_CONFIG
from app.core.exceptions import ConfigError
from app.models.alert_config import AlertConfig


class ConfigRepository:
    """CRUD for alert configuration entries, with an in-process cache."""

    def __init__(self, session: AsyncSession):
        self.session = session
        self._cache: dict[str, str] = {}
        self._loaded = False

    async def get_raw(self, key: str) -> Optional[AlertConfig]:
        result = await self.session.execute(
            select(AlertConfig).where(AlertConfig.config_key == key)
        )
        return result.scalar_one_or_none()

    async def refresh(self) -> None:
        result = await self.session.execute(select(AlertConfig))
        self._cache = {
            row.config_key: row.config_value
            for row in result.scalars().all()
        }
        self._loaded = True

    async def get(
        self,
        key: str,
        default: Optional[str] = None,
    ) -> Optional[str]:
        if not self._loaded:
            await self.refresh()

        if key in self._cache:
            return self._cache[key]

        if key in DEFAULT_CONFIG:
            return DEFAULT_CONFIG[key]

        return default

    async def get_required(self, key: str) -> str:
        value = await self.get(key)

        if value is None:
            raise ConfigError(f"Missing required config key: {key}")

        return value

    async def get_int(
        self,
        key: str,
        default: Optional[int] = None,
    ) -> int:
        raw = await self.get(key)

        if raw is None:
            if default is None:
                raise ConfigError(
                    f"Missing required int config key: {key}"
                )
            return default

        return int(raw)

    async def get_float(
        self,
        key: str,
        default: Optional[float] = None,
    ) -> float:
        raw = await self.get(key)

        if raw is None:
            if default is None:
                raise ConfigError(
                    f"Missing required float config key: {key}"
                )
            return default

        return float(raw)

    async def get_bool(
        self,
        key: str,
        default: bool = False,
    ) -> bool:
        raw = await self.get(key)

        if raw is None:
            return default

        return raw.strip().lower() in (
            "1",
            "true",
            "yes",
            "on",
        )

    async def set(
        self,
        key: str,
        value: str,
        updated_by: str,
    ) -> AlertConfig:
        """Insert or update an alert configuration value."""

        stmt = (
            pg_insert(AlertConfig)
            .values(
                config_key=key,
                config_value=value,
                updated_by=updated_by,
            )
            .on_conflict_do_update(
                index_elements=[AlertConfig.config_key],
                set_={
                    "config_value": value,
                    "updated_by": updated_by,
                },
            )
            .returning(AlertConfig)
        )

        result = await self.session.execute(stmt)
        row = result.scalar_one()

        self._cache[key] = value
        self._loaded = True

        return row

    async def delete(self, key: str) -> None:
        await self.session.execute(
            delete(AlertConfig).where(
                AlertConfig.config_key == key
            )
        )

        self._cache.pop(key, None)

    async def bootstrap_defaults(
        self,
        updated_by: str = "system:bootstrap",
    ) -> int:
        """Insert missing default configuration values."""

        await self.refresh()

        inserted = 0

        for key, value in DEFAULT_CONFIG.items():
            if key in self._cache:
                continue

            stmt = (
                pg_insert(AlertConfig)
                .values(
                    config_key=key,
                    config_value=value,
                    updated_by=updated_by,
                )
                .on_conflict_do_nothing(
                    index_elements=[AlertConfig.config_key]
                )
            )

            await self.session.execute(stmt)
            inserted += 1

        await self.refresh()

        return inserted