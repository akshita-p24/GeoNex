"""
app/routers/spatial.py

Spatial reference layer APIs for M4 GIS Dashboard:
- GET /api/v1/roads
- GET /api/v1/villages
- GET /api/v1/infrastructure
"""

from typing import List, Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.spatial import Road, Village, Infrastructure, InfrastructureCategory
from app.schemas.spatial import RoadResponse, VillageResponse, InfrastructureResponse
from app.schemas.field_report import GeoJSONFeatureCollection, GeoJSONFeature, GeoJSONGeometry

router = APIRouter(prefix="", tags=["Spatial Layers (GIS)"])


@router.get("/roads/geojson", response_model=GeoJSONFeatureCollection)
async def get_roads_geojson(db: AsyncSession = Depends(get_db)):
    """
    Returns roads layer (LINESTRING) in GeoJSON format for M4 Dashboard.
    """
    # Sample mock roads in NER region for initial demonstration
    sample_features = [
        GeoJSONFeature(
            type="Feature",
            geometry=GeoJSONGeometry(
                type="LineString",
                coordinates=[[91.73, 26.14], [92.05, 26.20], [92.75, 26.40]],
            ),
            properties={"name": "NH-27 (Guwahati-Nagaon Highway)", "category": "NATIONAL_HIGHWAY"},
        ),
        GeoJSONFeature(
            type="Feature",
            geometry=GeoJSONGeometry(
                type="LineString",
                coordinates=[[93.60, 27.55], [93.80, 27.70], [94.10, 27.90]],
            ),
            properties={"name": "Itanagar Border Road", "category": "BORDER_ROAD"},
        ),
    ]
    return GeoJSONFeatureCollection(type="FeatureCollection", features=sample_features)


@router.get("/villages", response_model=List[VillageResponse])
async def list_villages(
    district: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
):
    """
    Get list of villages with demographic and spatial coordinates.
    """
    query = select(Village)
    if district:
        query = query.where(Village.district == district)
    result = await db.execute(query.limit(limit))
    return result.scalars().all()


@router.get("/infrastructure", response_model=List[InfrastructureResponse])
async def list_infrastructure(
    category: Optional[InfrastructureCategory] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
):
    """
    Get list of critical assets (hospitals, schools, bridges).
    """
    query = select(Infrastructure)
    if category:
        query = query.where(Infrastructure.category == category)
    result = await db.execute(query.limit(limit))
    return result.scalars().all()
