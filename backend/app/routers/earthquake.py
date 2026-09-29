"""
Earthquake API routes.
"""

from fastapi import APIRouter, Query

from app.services.earthquake_service import get_recent_earthquakes
from app.services.earthquake_features import generate_earthquake_features


router = APIRouter(
    prefix="/earthquake",
    tags=["Earthquake"],
)


@router.get("/recent")
async def recent_earthquakes(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(200.0, gt=0, le=1000),
    hours: int = Query(72, gt=0, le=720),
    min_magnitude: float = Query(2.5, ge=0, le=10),
):
    earthquake_data = await get_recent_earthquakes(
        latitude=lat,
        longitude=lon,
        radius_km=radius_km,
        hours=hours,
        min_magnitude=min_magnitude,
    )

    earthquake_features = generate_earthquake_features(
        earthquake_data
    )

    return {
        **earthquake_data,
        "features": earthquake_features,
    }