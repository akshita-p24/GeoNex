"""
Read-only access to GeoNex M3's risk_predictions table.

M3 owns the risk_predictions table.

M5 reads the committed prediction and converts it into the internal
prediction representation expected by the M5 alerting pipeline.
"""

import asyncio
import logging
from dataclasses import dataclass
from typing import Optional
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.risk_prediction import RiskPrediction

logger = logging.getLogger(__name__)

_RETRY_BACKOFF_SECONDS = [2, 4, 8]

_GEOHASH_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"


@dataclass
class M5RiskPrediction:
    """M5-compatible representation of an M3 risk prediction."""

    prediction_id: UUID
    area_id: str
    risk_score: float
    risk_band: str
    confidence: Optional[float]
    prediction_timestamp: object
    model_version: Optional[str]
    created_at: object


def _geohash(latitude: float, longitude: float, precision: int = 5) -> str:
    """Encode latitude/longitude as a standard Base32 geohash."""

    lat_interval = [-90.0, 90.0]
    lon_interval = [-180.0, 180.0]

    bits = []
    even_bit = True

    while len(bits) < precision * 5:
        if even_bit:
            value = longitude
            interval = lon_interval
        else:
            value = latitude
            interval = lat_interval

        midpoint = (interval[0] + interval[1]) / 2

        if value >= midpoint:
            bits.append(1)
            interval[0] = midpoint
        else:
            bits.append(0)
            interval[1] = midpoint

        even_bit = not even_bit

    result = []

    for i in range(0, precision * 5, 5):
        value = 0

        for bit in bits[i:i + 5]:
            value = (value << 1) | bit

        result.append(_GEOHASH_BASE32[value])

    return "".join(result)


def _area_id_from_coordinates(
    latitude: float,
    longitude: float,
) -> str:
    """Generate the canonical 5-character GeoNex alert area ID."""

    return _geohash(
        latitude=float(latitude),
        longitude=float(longitude),
        precision=5,
    )


def _risk_band_from_m3(risk_level) -> str:
    """
    Convert M3 risk levels to M5 severity bands.

    M3 LOW means no active M5 incident, therefore it maps to NORMAL.
    """

    value = (
        risk_level.value
        if hasattr(risk_level, "value")
        else str(risk_level)
    )

    mapping = {
        "LOW": "NORMAL",
        "WATCH": "WATCH",
        "WARNING": "WARNING",
        "CRITICAL": "CRITICAL",
    }

    try:
        return mapping[value]
    except KeyError as exc:
        raise ValueError(
            f"Unrecognized M3 risk_level '{value}'"
        ) from exc


def _to_m5_prediction(
    prediction: RiskPrediction,
) -> M5RiskPrediction:
    """Convert an M3 ORM prediction into the M5 representation."""

    area_id = _area_id_from_coordinates(
        prediction.latitude,
        prediction.longitude,
    )

    return M5RiskPrediction(
        prediction_id=prediction.id,
        area_id=area_id,
        risk_score=float(prediction.risk_score),
        risk_band=_risk_band_from_m3(prediction.risk_level),
        confidence=(
            float(prediction.confidence)
            if prediction.confidence is not None
            else None
        ),
        prediction_timestamp=prediction.created_at,
        model_version=prediction.model_version,
        created_at=prediction.created_at,
    )


class RiskPredictionRepository:
    """Read-only repository for M3's risk_predictions table."""

    def __init__(self, session: AsyncSession):
        self.session = session

    async def get(
        self,
        prediction_id,
    ) -> Optional[M5RiskPrediction]:

        result = await self.session.execute(
            select(RiskPrediction).where(
                RiskPrediction.id == prediction_id
            )
        )

        prediction = result.scalar_one_or_none()

        if prediction is None:
            return None

        return _to_m5_prediction(prediction)

    async def get_with_retry(
        self,
        prediction_id,
    ) -> Optional[M5RiskPrediction]:
        """
        Re-read the committed M3 prediction.

        Retries after 2s, 4s and 8s if the row is not yet visible.
        """

        prediction = await self.get(prediction_id)

        if prediction is not None:
            return prediction

        for delay in _RETRY_BACKOFF_SECONDS:
            logger.info(
                "prediction_id=%s not yet visible, retrying in %ss",
                prediction_id,
                delay,
            )

            await asyncio.sleep(delay)

            prediction = await self.get(prediction_id)

            if prediction is not None:
                return prediction

        return None

    async def list_since(
        self,
        area_id: Optional[str],
        since,
        limit: int = 500,
    ) -> list[M5RiskPrediction]:
        """
        Retrieve recent M3 predictions for reconciliation.

        M3 does not store area_id, so the M5 area_id is calculated from
        latitude/longitude after retrieval.
        """

        stmt = (
            select(RiskPrediction)
            .where(RiskPrediction.created_at >= since)
            .order_by(
                RiskPrediction.created_at.asc(),
                RiskPrediction.id.asc(),
            )
            .limit(limit)
        )

        result = await self.session.execute(stmt)

        predictions = [
            _to_m5_prediction(row)
            for row in result.scalars().all()
        ]

        if area_id is not None:
            predictions = [
                prediction
                for prediction in predictions
                if prediction.area_id == area_id
            ]

        return predictions