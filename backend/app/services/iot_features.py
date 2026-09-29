from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.iot import IoTSensorReading


async def calculate_soil_moisture_features(
    db: AsyncSession,
    node_id,
    current_observed_at: datetime,
    current_soil_moisture: float | None,
) -> dict:
    """
    Calculate the five soil-moisture features expected by the
    existing Dynamic Trigger Random Forest model.

    Features:
        soil_moisture
        soil_moisture_3d_mean
        soil_moisture_7d_mean
        soil_moisture_change_3d
        soil_moisture_change_7d

    Historical windows exclude the current reading.
    """

    if current_observed_at.tzinfo is None:
        current_observed_at = current_observed_at.replace(
            tzinfo=timezone.utc
        )

    # --------------------------------------------------------
    # 3-day historical window
    # --------------------------------------------------------

    three_days_ago = current_observed_at - timedelta(days=3)

    result_3d = await db.execute(
        select(IoTSensorReading.soil_moisture)
        .where(
            IoTSensorReading.node_id == node_id,
            IoTSensorReading.observed_at >= three_days_ago,
            IoTSensorReading.observed_at < current_observed_at,
            IoTSensorReading.soil_moisture.is_not(None),
        )
        .order_by(IoTSensorReading.observed_at.asc())
    )

    values_3d = [
        value
        for value in result_3d.scalars().all()
        if value is not None
    ]

    # --------------------------------------------------------
    # 7-day historical window
    # --------------------------------------------------------

    seven_days_ago = current_observed_at - timedelta(days=7)

    result_7d = await db.execute(
        select(IoTSensorReading.soil_moisture)
        .where(
            IoTSensorReading.node_id == node_id,
            IoTSensorReading.observed_at >= seven_days_ago,
            IoTSensorReading.observed_at < current_observed_at,
            IoTSensorReading.soil_moisture.is_not(None),
        )
        .order_by(IoTSensorReading.observed_at.asc())
    )

    values_7d = [
        value
        for value in result_7d.scalars().all()
        if value is not None
    ]

    # --------------------------------------------------------
    # Calculate historical means
    # --------------------------------------------------------

    soil_moisture_3d_mean = (
        sum(values_3d) / len(values_3d)
        if values_3d
        else None
    )

    soil_moisture_7d_mean = (
        sum(values_7d) / len(values_7d)
        if values_7d
        else None
    )

    # --------------------------------------------------------
    # Calculate changes
    #
    # Positive value = current moisture is higher than the
    # historical average.
    # --------------------------------------------------------

    soil_moisture_change_3d = (
        current_soil_moisture - soil_moisture_3d_mean
        if current_soil_moisture is not None
        and soil_moisture_3d_mean is not None
        else None
    )

    soil_moisture_change_7d = (
        current_soil_moisture - soil_moisture_7d_mean
        if current_soil_moisture is not None
        and soil_moisture_7d_mean is not None
        else None
    )

    return {
        "soil_moisture": current_soil_moisture,
        "soil_moisture_3d_mean": soil_moisture_3d_mean,
        "soil_moisture_7d_mean": soil_moisture_7d_mean,
        "soil_moisture_change_3d": soil_moisture_change_3d,
        "soil_moisture_change_7d": soil_moisture_change_7d,
    }