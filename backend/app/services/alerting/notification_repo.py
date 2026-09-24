"""
Repository for M5 NotificationIntent and AlertDelivery.
"""

from typing import Optional

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.enums import (
    DeliveryStatus,
    FailureType,
    NotificationIntentStatus,
)
from app.models.alert import AlertDelivery
from app.models.notification import NotificationIntent


class NotificationRepository:
    """CRUD operations for notification intents and deliveries."""

    def __init__(self, session: AsyncSession):
        self.session = session

    # ---------------------------------------------------------
    # NotificationIntent
    # ---------------------------------------------------------

    async def get_intent_by_id(
        self,
        trigger_id,
    ) -> Optional[NotificationIntent]:

        result = await self.session.execute(
            select(NotificationIntent).where(
                NotificationIntent.notification_trigger_id == trigger_id
            )
        )

        return result.scalar_one_or_none()

    async def create_intent(
        self,
        **kwargs,
    ) -> NotificationIntent:

        obj = NotificationIntent(**kwargs)

        self.session.add(obj)

        await self.session.flush()
        await self.session.refresh(obj)

        return obj

    async def set_intent_status(
        self,
        trigger_id,
        status: NotificationIntentStatus,
    ) -> None:

        await self.session.execute(
            update(NotificationIntent)
            .where(
                NotificationIntent.notification_trigger_id == trigger_id
            )
            .values(status=status)
        )

    async def claim_pending_batch(
        self,
        batch_size: int,
    ) -> list[NotificationIntent]:

        result = await self.session.execute(
            select(NotificationIntent)
            .where(
                NotificationIntent.status
                == NotificationIntentStatus.PENDING
            )
            .order_by(NotificationIntent.created_at.asc())
            .limit(batch_size)
            .with_for_update(skip_locked=True)
        )

        intents = list(result.scalars().all())

        if intents:
            ids = [
                intent.notification_trigger_id
                for intent in intents
            ]

            await self.session.execute(
                update(NotificationIntent)
                .where(
                    NotificationIntent.notification_trigger_id.in_(ids)
                )
                .values(
                    status=NotificationIntentStatus.DISPATCHING
                )
            )

        return intents

    # ---------------------------------------------------------
    # AlertDelivery
    # ---------------------------------------------------------

    async def get_delivery_by_id(
        self,
        delivery_id,
    ) -> Optional[AlertDelivery]:

        result = await self.session.execute(
            select(AlertDelivery).where(
                AlertDelivery.delivery_id == delivery_id
            )
        )

        return result.scalar_one_or_none()

    async def get_existing_delivery(
        self,
        alert_id,
        recipient_id: str,
        channel,
        notification_trigger_id,
    ) -> Optional[AlertDelivery]:

        result = await self.session.execute(
            select(AlertDelivery).where(
                AlertDelivery.alert_id == alert_id,
                AlertDelivery.recipient_id == recipient_id,
                AlertDelivery.channel == channel,
                AlertDelivery.notification_trigger_id
                == notification_trigger_id,
            )
        )

        return result.scalar_one_or_none()

    async def get_or_create_pending_delivery(
        self,
        **kwargs,
    ) -> tuple[AlertDelivery, bool]:
        """
        Insert a PENDING delivery idempotently.

        Existing delivery rows are reused instead of duplicated.
        """

        # The actual M3 database column is `recipient`,
        # not `recipient_id`.
        insert_kwargs = dict(kwargs)

        if "recipient_id" in insert_kwargs:
            insert_kwargs["recipient"] = insert_kwargs.pop(
                "recipient_id"
            )

        stmt = (
            pg_insert(AlertDelivery)
            .values(**insert_kwargs)
            .on_conflict_do_nothing(
                index_elements=[
                    "alert_id",
                    "recipient",
                    "channel",
                    "notification_trigger_id",
                ]
            )
            .returning(AlertDelivery)
        )

        result = await self.session.execute(stmt)

        row = result.first()

        if row is not None:
            return row[0], True

        existing = await self.get_existing_delivery(
            kwargs["alert_id"],
            kwargs["recipient_id"],
            kwargs["channel"],
            kwargs["notification_trigger_id"],
        )

        return existing, False

    async def update_delivery_status(
        self,
        delivery_id,
        status: DeliveryStatus,
        **extra,
    ) -> None:

        await self.session.execute(
            update(AlertDelivery)
            .where(
                AlertDelivery.delivery_id == delivery_id
            )
            .values(
                status=status,
                **extra,
            )
        )

    async def list_retryable_deliveries(
        self,
        limit: int = 500,
    ) -> list[AlertDelivery]:

        result = await self.session.execute(
            select(AlertDelivery)
            .where(
                AlertDelivery.status.in_(
                    [
                        DeliveryStatus.PENDING,
                        DeliveryStatus.SENDING,
                    ]
                )
            )
            .limit(limit)
        )

        return list(result.scalars().all())

    async def list_transient_failed_intent_ids(
        self,
        max_retries: int,
        limit: int = 500,
    ) -> list:

        result = await self.session.execute(
            select(
                AlertDelivery.notification_trigger_id
            )
            .where(
                AlertDelivery.status
                == DeliveryStatus.FAILED,
                AlertDelivery.error_type
                == FailureType.TRANSIENT,
                AlertDelivery.attempt_count
                < max_retries,
            )
            .distinct()
            .limit(limit)
        )

        return [
            row[0]
            for row in result.all()
        ]