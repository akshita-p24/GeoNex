"""
app/models/alert.py

SQLAlchemy models for Early Warning Alerts (M3 + M5 integration).
"""

import uuid
from datetime import datetime
from enum import Enum as PyEnum

from geoalchemy2 import Geometry
from sqlalchemy import (
    String,
    Text,
    DateTime,
    Enum,
    ForeignKey,
    func,
    Index,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import (
    Mapped,
    mapped_column,
    relationship,
    synonym,
)

from app.core.database import Base
from app.models.risk_prediction import RiskLevel
from app.core.enums import (
    Severity,
    LifecycleStatus,
)


# ============================================================
# M3 enums — kept for existing GeoNex API compatibility
# ============================================================

class AlertStatus(str, PyEnum):
    ACTIVE = "ACTIVE"
    ACKNOWLEDGED = "ACKNOWLEDGED"
    RESOLVED = "RESOLVED"
    CANCELLED = "CANCELLED"
    EXPIRED = "EXPIRED"


class DeliveryChannel(str, PyEnum):
    SMS = "SMS"
    PUSH = "PUSH"
    APP = "APP"
    EMAIL = "EMAIL"


class DeliveryStatus(str, PyEnum):
    PENDING = "PENDING"
    SENDING = "SENDING"
    SENT = "SENT"
    DELIVERED = "DELIVERED"
    FAILED = "FAILED"


# ============================================================
# Alert
# ============================================================

class Alert(Base):
    __tablename__ = "alerts"

    # --------------------------------------------------------
    # Existing M3 primary key
    # --------------------------------------------------------

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    # M5 expects alert_id.
    # Keep the actual database column as "id".
    alert_id = synonym("id")

    # --------------------------------------------------------
    # Existing M3 relationship to risk prediction
    # --------------------------------------------------------

    risk_prediction_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "risk_predictions.id",
            ondelete="SET NULL",
        ),
        nullable=True,
    )

    # --------------------------------------------------------
    # Existing M3 severity
    #
    # LOW / WATCH / WARNING / CRITICAL
    # --------------------------------------------------------

    severity: Mapped[RiskLevel] = mapped_column(
        Enum(
            RiskLevel,
            name="risk_level",
            create_type=False,
        ),
        nullable=False,
        index=True,
    )

    # --------------------------------------------------------
    # Existing M3 lifecycle status
    # --------------------------------------------------------

    status: Mapped[AlertStatus] = mapped_column(
        Enum(
            AlertStatus,
            name="alert_status",
            create_type=False,
        ),
        default=AlertStatus.ACTIVE,
        nullable=False,
        index=True,
    )

    # --------------------------------------------------------
    # Existing M3 display fields
    # --------------------------------------------------------

    title: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )

    message: Mapped[str] = mapped_column(
        Text,
        nullable=False,
    )

    # --------------------------------------------------------
    # Existing M3 PostGIS area
    # --------------------------------------------------------

    geographic_area: Mapped[str | None] = mapped_column(
        Geometry(
            geometry_type="POLYGON",
            srid=4326,
        ),
        nullable=True,
    )

    # --------------------------------------------------------
    # Existing M3 acknowledgement fields
    # --------------------------------------------------------

    acknowledged_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    acknowledged_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "users.id",
            ondelete="SET NULL",
        ),
        nullable=True,
    )

    # --------------------------------------------------------
    # Existing M3 creation timestamp
    # --------------------------------------------------------

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
    )

    # ========================================================
    # M5 ALERT ENGINE FIELDS
    # ========================================================

    # Canonical 5-character geohash area identifier.
    area_id: Mapped[str | None] = mapped_column(
        String,
        nullable=True,
        index=True,
    )

    # M5 severity state:
    # NORMAL / WATCH / WARNING / CRITICAL
    current_severity: Mapped[Severity] = mapped_column(
        Enum(
            Severity,
            name="severity",
            create_type=False,
        ),
        nullable=False,
        default=Severity.NORMAL,
    )

    candidate_severity: Mapped[Severity | None] = mapped_column(
        Enum(
            Severity,
            name="severity",
            create_type=False,
        ),
        nullable=True,
    )

    candidate_since: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    candidate_confirmations: Mapped[int] = mapped_column(
        default=0,
        server_default="0",
        nullable=False,
    )

    # M5 lifecycle:
    # ACTIVE / ACKNOWLEDGED / RESOLVED / CANCELLED / EXPIRED
    lifecycle_status: Mapped[LifecycleStatus] = mapped_column(
        Enum(
            LifecycleStatus,
            name="lifecycle_status",
            create_type=False,
        ),
        nullable=False,
        default=LifecycleStatus.ACTIVE,
    )

    band_entered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    last_prediction_timestamp: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    last_evaluated_prediction_timestamp: Mapped[
        datetime | None
    ] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    last_evaluated_created_at: Mapped[
        datetime | None
    ] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    last_evaluated_prediction_id: Mapped[
        uuid.UUID | None
    ] = mapped_column(
        UUID(as_uuid=True),
        nullable=True,
    )

    last_risk_score: Mapped[float | None] = mapped_column(
        nullable=True,
    )

    last_confidence: Mapped[float | None] = mapped_column(
        nullable=True,
    )

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    resolved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    cancelled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    expired_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    # --------------------------------------------------------
    # Relationship
    # --------------------------------------------------------

    deliveries = relationship(
        "AlertDelivery",
        back_populates="alert",
        cascade="all, delete-orphan",
    )


# ============================================================
# Alert Delivery
# ============================================================

class AlertDelivery(Base):
    __tablename__ = "alert_deliveries"

    # --------------------------------------------------------
    # Existing M3 primary key
    # --------------------------------------------------------

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    # M5 expects delivery_id.
    delivery_id = synonym("id")

    # --------------------------------------------------------
    # Alert FK
    # --------------------------------------------------------

    alert_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "alerts.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    # --------------------------------------------------------
    # Delivery channel
    # --------------------------------------------------------

    channel: Mapped[DeliveryChannel] = mapped_column(
        Enum(
            DeliveryChannel,
            name="delivery_channel",
            create_type=False,
        ),
        nullable=False,
    )

    # --------------------------------------------------------
    # Delivery status
    # --------------------------------------------------------

    status: Mapped[DeliveryStatus] = mapped_column(
        Enum(
            DeliveryStatus,
            name="delivery_status",
            create_type=False,
        ),
        default=DeliveryStatus.PENDING,
        nullable=False,
    )

    # --------------------------------------------------------
    # Existing M3 recipient
    # --------------------------------------------------------

    recipient: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )

    # M5 expects recipient_id.
    recipient_id = synonym("recipient")

    error_message: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
    )

    sent_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # ========================================================
    # M5 delivery fields
    # ========================================================

    notification_trigger_id: Mapped[
        uuid.UUID | None
    ] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(
            "notification_intents.notification_trigger_id",
            ondelete="CASCADE",
        ),
        nullable=True,
    )

    provider_message_id: Mapped[str | None] = mapped_column(
        String,
        nullable=True,
    )

    attempt_count: Mapped[int] = mapped_column(
        default=0,
        server_default="0",
        nullable=False,
    )

    last_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    delivered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    error_type: Mapped[str | None] = mapped_column(
        String,
        nullable=True,
    )

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # --------------------------------------------------------
    # Relationship
    # --------------------------------------------------------

    alert = relationship(
        "Alert",
        back_populates="deliveries",
    )


# ============================================================
# Existing spatial index
# ============================================================

Index(
    "idx_alerts_area",
    Alert.geographic_area,
    postgresql_using="gist",
)