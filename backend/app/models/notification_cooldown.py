from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, Enum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.enums import DeliveryChannel


class NotificationCooldown(Base):
    __tablename__ = "notification_cooldowns"

    alert_id: Mapped[UUID] = mapped_column(
        ForeignKey("alerts.id", ondelete="CASCADE"),
        primary_key=True,
    )

    channel: Mapped[DeliveryChannel] = mapped_column(
        Enum(
            DeliveryChannel,
            name="delivery_channel",
            create_type=False,
        ),
        primary_key=True,
    )

    trigger_type: Mapped[str] = mapped_column(
        String,
        primary_key=True,
    )

    cooldown_until: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )