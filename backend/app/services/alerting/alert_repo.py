"""Repository for the GeoNex M5 Alert entity."""

import hashlib
from typing import Optional

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.enums import OPEN_LIFECYCLE_STATUSES
from app.models.alert import Alert


def area_lock_key(area_id: str) -> int:
    """Return a deterministic signed 64-bit advisory-lock key."""
    digest = hashlib.sha256(area_id.encode("utf-8")).digest()

    return int.from_bytes(
        digest[:8],
        byteorder="big",
        signed=True,
    )


class AlertRepository:
    """CRUD and area-scoped queries for the M5 Alert model."""

    def __init__(self, session: AsyncSession):
        self.session = session

    async def acquire_area_lock(self, area_id: str) -> None:
        """Serialize concurrent evaluations for the same area."""

        await self.session.execute(
            text(
                "SELECT pg_advisory_xact_lock(:key)"
            ),
            {
                "key": area_lock_key(area_id),
            },
        )

    async def get_by_id(
        self,
        alert_id,
    ) -> Optional[Alert]:
        """Get an alert by its UUID."""

        result = await self.session.execute(
            select(Alert).where(
                Alert.alert_id == alert_id
            )
        )

        return result.scalar_one_or_none()

    async def get_open_for_area(
        self,
        area_id: str,
    ) -> Optional[Alert]:
        """
        Return the single ACTIVE/ACKNOWLEDGED alert
        for an area, if one exists.

        Must be called after acquire_area_lock().
        """

        result = await self.session.execute(
            select(Alert).where(
                Alert.area_id == area_id,
                Alert.lifecycle_status.in_(
                    list(OPEN_LIFECYCLE_STATUSES)
                ),
            )
        )

        return result.scalar_one_or_none()

    async def get_latest_for_area(
        self,
        area_id: str,
    ) -> Optional[Alert]:
        """
        Return the most recently updated alert for an area,
        including terminal alerts.
        """

        result = await self.session.execute(
            select(Alert)
            .where(Alert.area_id == area_id)
            .order_by(Alert.updated_at.desc())
            .limit(1)
        )

        return result.scalar_one_or_none()

    async def create(self, **kwargs) -> Alert:
        """Create and flush an alert."""

        obj = Alert(**kwargs)

        self.session.add(obj)

        await self.session.flush()
        await self.session.refresh(obj)

        return obj

    async def save(self, alert: Alert) -> Alert:
        """Flush changes to an existing alert."""

        await self.session.flush()

        return alert