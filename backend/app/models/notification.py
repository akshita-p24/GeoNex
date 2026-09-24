"""
app/models/notification.py

M5 NotificationIntent model.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, String, func, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.enums import (
    NotificationIntentStatus,
    Severity,
    TriggerType,
)


class NotificationIntent(Base):
    __tablename__ = "notification_intents"

    notification_trigger_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )

    alert_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "alerts.id",
            ondelete="CASCADE",
        ),
        nullable=False,
    )

    trigger_type: Mapped[TriggerType] = mapped_column(
        Enum(
            TriggerType,
            name="trigger_type",
            create_type=False,
        ),
        nullable=False,
    )

    severity: Mapped[Severity] = mapped_column(
        Enum(
            Severity,
            name="severity",
            create_type=False,
        ),
        nullable=False,
    )

    template_key: Mapped[str] = mapped_column(
        String,
        nullable=False,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    status: Mapped[NotificationIntentStatus] = mapped_column(
        Enum(
            NotificationIntentStatus,
            name="notification_intent_status",
            create_type=False,
        ),
        nullable=False,
        server_default="PENDING",
    )


Index(
    "ix_notification_intents_status",
    NotificationIntent.status,
)

Index(
    "ix_notification_intents_alert_id",
    NotificationIntent.alert_id,
)