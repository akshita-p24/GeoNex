from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.notification_subscription import NotificationSubscription
from app.models.user import User


router = APIRouter(
    prefix="/recipients",
    tags=["Recipients"],
)


@router.post("/resolve")
async def resolve_recipients(
    payload: dict[str, Any],
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(
            NotificationSubscription,
            User,
        )
        .join(
            User,
            User.id == NotificationSubscription.user_id,
        )
        .where(
            User.is_active.is_(True),
            NotificationSubscription.is_active.is_(True),
        )
        .order_by(
            NotificationSubscription.priority.asc(),
        )
    )

    rows = result.all()

    recipients = []

    for subscription, user in rows:
        channel = subscription.channel.value

        recipient = {
            "recipient_id": str(subscription.id),
            "user_id": str(user.id),
            "preferred_channels": [channel],
            "priority": subscription.priority,
            "preferred_locale": subscription.preferred_locale,
            "phone_number": None,
            "device_token": None,
        }

        if channel == "SMS":
            recipient["phone_number"] = subscription.destination

        elif channel == "PUSH":
            recipient["device_token"] = subscription.destination

        elif channel == "APP":
            # APP notifications are handled by the
            # backend demo provider.
            pass

        recipients.append(recipient)

    return recipients