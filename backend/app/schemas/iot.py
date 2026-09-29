"""
app/schemas/iot.py

Pydantic schemas for IoT sensor nodes and sensor readings.
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class IoTSensorNodeCreate(BaseModel):
    """
    Request schema for registering an IoT sensor node.
    """

    node_id: str = Field(
        ...,
        min_length=1,
        max_length=100,
    )

    latitude: float = Field(
        ...,
        ge=-90,
        le=90,
    )

    longitude: float = Field(
        ...,
        ge=-180,
        le=180,
    )

    is_active: bool = True


class IoTSensorNodeResponse(BaseModel):
    """
    Response schema for an IoT sensor node.
    """

    id: UUID
    node_id: str
    latitude: float
    longitude: float
    is_active: bool
    last_seen: datetime | None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class IoTSensorReadingCreate(BaseModel):
    """
    Sensor reading sent by an IoT node.

    All sensor measurements are optional because a node may
    provide only some sensors at a particular time.
    """

    node_id: str = Field(
        ...,
        min_length=1,
        max_length=100,
    )

    observed_at: datetime

    soil_moisture: float | None = Field(
        default=None,
        ge=0,
        le=100,
    )

    acceleration_x: float | None = None
    acceleration_y: float | None = None
    acceleration_z: float | None = None

    gyroscope_x: float | None = None
    gyroscope_y: float | None = None
    gyroscope_z: float | None = None

class IoTSensorReadingResponse(BaseModel):
    """
    Response schema for a stored IoT sensor reading,
    including calculated soil-moisture ML features.
    """

    id: UUID
    node_id: UUID
    observed_at: datetime

    soil_moisture: float | None

    acceleration_x: float | None
    acceleration_y: float | None
    acceleration_z: float | None

    gyroscope_x: float | None
    gyroscope_y: float | None
    gyroscope_z: float | None

    # Calculated ML features
    soil_moisture_3d_mean: float | None = None
    soil_moisture_7d_mean: float | None = None
    soil_moisture_change_3d: float | None = None
    soil_moisture_change_7d: float | None = None

    created_at: datetime

    class Config:
        from_attributes = True