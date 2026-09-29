"""
app/models/iot.py

SQLAlchemy models for ESP32-based IoT sensor nodes and readings.
"""

import uuid
from datetime import datetime

from geoalchemy2 import Geometry
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Index, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class IoTSensorNode(Base):
    """
    Represents a physical or planned ESP32 sensor node.
    """

    __tablename__ = "iot_sensor_nodes"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    node_id: Mapped[str] = mapped_column(
        String(100),
        unique=True,
        nullable=False,
        index=True,
    )

    latitude: Mapped[float] = mapped_column(
        Float,
        nullable=False,
    )

    longitude: Mapped[float] = mapped_column(
        Float,
        nullable=False,
    )

    location: Mapped[str] = mapped_column(
        Geometry(geometry_type="POINT", srid=4326),
        nullable=False,
    )

    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )

    last_seen: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class IoTSensorReading(Base):
    """
    Stores measurements received from an ESP32 IoT node.

    Soil moisture is optional because the node may send only
    motion/tilt data in some situations.
    """

    __tablename__ = "iot_sensor_readings"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )

    node_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("iot_sensor_nodes.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        index=True,
    )

    soil_moisture: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    acceleration_x: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    acceleration_y: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    acceleration_z: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    gyroscope_x: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    gyroscope_y: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    gyroscope_z: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )


Index(
    "idx_iot_sensor_nodes_location",
    IoTSensorNode.location,
    postgresql_using="gist",
)

Index(
    "idx_iot_sensor_readings_node_time",
    IoTSensorReading.node_id,
    IoTSensorReading.observed_at,
)