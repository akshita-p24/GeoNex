"""
app/routers/iot.py

API endpoints for IoT sensor nodes and sensor readings.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from geoalchemy2 import WKTElement
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.iot import IoTSensorNode, IoTSensorReading
from app.schemas.iot import (
    IoTSensorNodeCreate,
    IoTSensorNodeResponse,
    IoTSensorReadingCreate,
    IoTSensorReadingResponse,
)
from app.services.iot_features import calculate_soil_moisture_features


router = APIRouter(
    prefix="/iot",
    tags=["IoT Sensors"],
)


@router.post(
    "/nodes",
    response_model=IoTSensorNodeResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_sensor_node(
    node_in: IoTSensorNodeCreate,
    db: AsyncSession = Depends(get_db),
):
    """
    Register a new IoT sensor node.
    """

    existing = await db.execute(
        select(IoTSensorNode).where(
            IoTSensorNode.node_id == node_in.node_id
        )
    )

    if existing.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Sensor node '{node_in.node_id}' already exists.",
        )

    node = IoTSensorNode(
        node_id=node_in.node_id,
        latitude=node_in.latitude,
        longitude=node_in.longitude,
        location=WKTElement(
            f"POINT({node_in.longitude} {node_in.latitude})",
            srid=4326,
        ),
        is_active=node_in.is_active,
    )

    db.add(node)

    await db.flush()
    await db.refresh(node)

    return node


@router.get(
    "/nodes",
    response_model=list[IoTSensorNodeResponse],
)
async def list_sensor_nodes(
    db: AsyncSession = Depends(get_db),
):
    """
    Return all registered IoT sensor nodes.
    """

    result = await db.execute(
        select(IoTSensorNode).order_by(
            IoTSensorNode.created_at.desc()
        )
    )

    return result.scalars().all()


@router.get(
    "/nodes/{node_id}",
    response_model=IoTSensorNodeResponse,
)
async def get_sensor_node(
    node_id: str,
    db: AsyncSession = Depends(get_db),
):
    """
    Return one IoT sensor node.
    """

    result = await db.execute(
        select(IoTSensorNode).where(
            IoTSensorNode.node_id == node_id
        )
    )

    node = result.scalar_one_or_none()

    if node is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Sensor node '{node_id}' not found.",
        )

    return node


@router.post(
    "/sensor-data",
    response_model=IoTSensorReadingResponse,
    status_code=status.HTTP_201_CREATED,
)
async def receive_sensor_data(
    reading_in: IoTSensorReadingCreate,
    db: AsyncSession = Depends(get_db),
):
    """
    Receive and store a sensor reading.

    This endpoint can be called by:
    - PowerShell/Postman during development
    - ESP32 later

    The endpoint also calculates the five soil-moisture
    features required by the existing ML model.
    """

    # --------------------------------------------------------
    # Find sensor node
    # --------------------------------------------------------

    result = await db.execute(
        select(IoTSensorNode).where(
            IoTSensorNode.node_id == reading_in.node_id
        )
    )

    node = result.scalar_one_or_none()

    if node is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=(
                f"Sensor node '{reading_in.node_id}' "
                "is not registered."
            ),
        )

    if not node.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Sensor node '{reading_in.node_id}' "
                "is inactive."
            ),
        )

    # --------------------------------------------------------
    # Normalize timestamp
    # --------------------------------------------------------

    observed_at = reading_in.observed_at

    if observed_at.tzinfo is None:
        observed_at = observed_at.replace(
            tzinfo=timezone.utc
        )

    # --------------------------------------------------------
    # Calculate soil-moisture ML features
    # --------------------------------------------------------

    soil_features = await calculate_soil_moisture_features(
        db=db,
        node_id=node.id,
        current_observed_at=observed_at,
        current_soil_moisture=reading_in.soil_moisture,
    )

    # --------------------------------------------------------
    # Create raw sensor reading
    # --------------------------------------------------------

    reading = IoTSensorReading(
        node_id=node.id,
        observed_at=observed_at,
        soil_moisture=reading_in.soil_moisture,
        acceleration_x=reading_in.acceleration_x,
        acceleration_y=reading_in.acceleration_y,
        acceleration_z=reading_in.acceleration_z,
        gyroscope_x=reading_in.gyroscope_x,
        gyroscope_y=reading_in.gyroscope_y,
        gyroscope_z=reading_in.gyroscope_z,
    )

    node.last_seen = datetime.now(timezone.utc)

    db.add(reading)

    await db.flush()
    await db.refresh(reading)

    # --------------------------------------------------------
    # Build response including calculated ML features
    # --------------------------------------------------------

    return {
        "id": reading.id,
        "node_id": reading.node_id,
        "observed_at": reading.observed_at,
        "soil_moisture": reading.soil_moisture,
        "acceleration_x": reading.acceleration_x,
        "acceleration_y": reading.acceleration_y,
        "acceleration_z": reading.acceleration_z,
        "gyroscope_x": reading.gyroscope_x,
        "gyroscope_y": reading.gyroscope_y,
        "gyroscope_z": reading.gyroscope_z,
        "soil_moisture_3d_mean": soil_features[
            "soil_moisture_3d_mean"
        ],
        "soil_moisture_7d_mean": soil_features[
            "soil_moisture_7d_mean"
        ],
        "soil_moisture_change_3d": soil_features[
            "soil_moisture_change_3d"
        ],
        "soil_moisture_change_7d": soil_features[
            "soil_moisture_change_7d"
        ],
        "created_at": reading.created_at,
    }


@router.get(
    "/nodes/{node_id}/readings",
    response_model=list[IoTSensorReadingResponse],
)
async def get_sensor_readings(
    node_id: str,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
):
    """
    Return recent readings for a sensor node.
    """

    if limit < 1 or limit > 500:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="limit must be between 1 and 500.",
        )

    node_result = await db.execute(
        select(IoTSensorNode).where(
            IoTSensorNode.node_id == node_id
        )
    )

    node = node_result.scalar_one_or_none()

    if node is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Sensor node '{node_id}' not found.",
        )

    result = await db.execute(
        select(IoTSensorReading)
        .where(
            IoTSensorReading.node_id == node.id
        )
        .order_by(
            IoTSensorReading.observed_at.desc()
        )
        .limit(limit)
    )

    return result.scalars().all()