"""
Risk Prediction API Endpoints.

M1 ML integration:
- GET /api/v1/risk/location
- GET /api/v1/risk/area
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Query

from app.services.ml_service import ml_service
from app.schemas.risk import RiskResponse
from app.schemas.field_report import (
    GeoJSONFeatureCollection,
    GeoJSONFeature,
    GeoJSONGeometry,
)

router = APIRouter(prefix="/risk", tags=["Landslide Risk"])


@router.get("/location", response_model=RiskResponse)
async def get_risk_by_location(
    lat: float = Query(
        ...,
        ge=-90.0,
        le=90.0,
        description="Latitude",
    ),
    lon: float = Query(
        ...,
        ge=-180.0,
        le=180.0,
        description="Longitude",
    ),

    # -----------------------------
    # STATIC FEATURES
    # -----------------------------
    elevation: float = Query(500.0),
    slope: float = Query(25.0),
    curvature: float = Query(0.0),
    soil_type: float = Query(1.0),
    ndvi_2017: float = Query(0.5),
    distance_to_river_m: float = Query(1000.0),
    distance_to_road_m: float = Query(1000.0),
    distance_to_village_m: float = Query(2000.0),
    aspect_sin: float = Query(0.0),
    aspect_cos: float = Query(1.0),

    # -----------------------------
    # DYNAMIC FEATURES
    # -----------------------------
    rainfall_1d: float = Query(20.0),
    rainfall_3d: float = Query(40.0),
    rainfall_7d: float = Query(70.0),
    rainfall_14d: float = Query(100.0),
    rainfall_30d: float = Query(150.0),
    rainfall_max_3d: float = Query(25.0),
    rainfall_max_7d: float = Query(30.0),
    rainy_days_7d: float = Query(3.0),
    rainy_days_14d: float = Query(5.0),
    rainy_days_30d: float = Query(10.0),
    soil_moisture: float = Query(0.42),
    soil_moisture_3d_mean: float = Query(0.40),
    soil_moisture_7d_mean: float = Query(0.38),
    soil_moisture_change_3d: float = Query(0.02),
    soil_moisture_change_7d: float = Query(0.04),
):
    """
    Get AI landslide risk prediction for a specific coordinate.

    This endpoint sends the complete M1 static and dynamic
    feature set to the actual Random Forest inference engine.
    """

    static_features = {
        "elevation": elevation,
        "slope": slope,
        "curvature": curvature,
        "soil_type": soil_type,
        "ndvi_2017": ndvi_2017,
        "distance_to_river_m": distance_to_river_m,
        "distance_to_road_m": distance_to_road_m,
        "distance_to_village_m": distance_to_village_m,
        "aspect_sin": aspect_sin,
        "aspect_cos": aspect_cos,
    }

    dynamic_features = {
        "rainfall_1d": rainfall_1d,
        "rainfall_3d": rainfall_3d,
        "rainfall_7d": rainfall_7d,
        "rainfall_14d": rainfall_14d,
        "rainfall_30d": rainfall_30d,
        "rainfall_max_3d": rainfall_max_3d,
        "rainfall_max_7d": rainfall_max_7d,
        "rainy_days_7d": rainy_days_7d,
        "rainy_days_14d": rainy_days_14d,
        "rainy_days_30d": rainy_days_30d,
        "soil_moisture": soil_moisture,
        "soil_moisture_3d_mean": soil_moisture_3d_mean,
        "soil_moisture_7d_mean": soil_moisture_7d_mean,
        "soil_moisture_change_3d": soil_moisture_change_3d,
        "soil_moisture_change_7d": soil_moisture_change_7d,
    }

    prediction = await ml_service.predict_risk(
        {
            "static_features": static_features,
            "dynamic_features": dynamic_features,
        }
    )

    # RiskResponse is currently based on the older M3 schema.
    # We map the actual M1 final risk into the existing fields.
    return RiskResponse(
        latitude=lat,
        longitude=lon,
        risk_score=prediction["dynamic_score"],
        risk_level=prediction["final_risk"],
        confidence=prediction.get("confidence", 0.0),
        model_version=prediction["model_version"],
        feature_snapshot={
            "static": static_features,
            "dynamic": dynamic_features,
            "static_score": prediction["static_score"],
            "static_class": prediction["static_class"],
            "dynamic_score": prediction["dynamic_score"],
            "dynamic_class": prediction["dynamic_class"],
            "final_risk": prediction["final_risk"],
        },
        timestamp=datetime.now(timezone.utc),
    )


@router.get("/area", response_model=GeoJSONFeatureCollection)
async def get_risk_area(
    min_lat: float = Query(26.0),
    max_lat: float = Query(28.0),
    min_lon: float = Query(91.0),
    max_lon: float = Query(94.0),
):
    """
    Return a simulated GeoJSON risk grid.

    Area-level real feature extraction will be connected
    to the spatial/PostGIS pipeline later.
    """

    features = []

    lat_steps = 3
    lon_steps = 3

    lat_delta = (max_lat - min_lat) / lat_steps
    lon_delta = (max_lon - min_lon) / lon_steps

    for i in range(lat_steps):
        for j in range(lon_steps):

            c_lat = min_lat + (i + 0.5) * lat_delta
            c_lon = min_lon + (j + 0.5) * lon_delta

            pred = await ml_service.predict_risk(
                {
                    "static_features": {
                        "elevation": 500.0,
                        "slope": 30.0,
                        "curvature": 0.0,
                        "soil_type": 1.0,
                        "ndvi_2017": 0.5,
                        "distance_to_river_m": 1000.0,
                        "distance_to_road_m": 1000.0,
                        "distance_to_village_m": 2000.0,
                        "aspect_sin": 0.0,
                        "aspect_cos": 1.0,
                    },
                    "dynamic_features": {
                        "rainfall_1d": 55.0,
                        "rainfall_3d": 80.0,
                        "rainfall_7d": 120.0,
                        "rainfall_14d": 160.0,
                        "rainfall_30d": 220.0,
                        "rainfall_max_3d": 55.0,
                        "rainfall_max_7d": 60.0,
                        "rainy_days_7d": 4.0,
                        "rainy_days_14d": 7.0,
                        "rainy_days_30d": 12.0,
                        "soil_moisture": 0.50,
                        "soil_moisture_3d_mean": 0.48,
                        "soil_moisture_7d_mean": 0.45,
                        "soil_moisture_change_3d": 0.03,
                        "soil_moisture_change_7d": 0.05,
                    },
                }
            )

            feature = GeoJSONFeature(
                type="Feature",
                geometry=GeoJSONGeometry(
                    type="Point",
                    coordinates=[
                        round(c_lon, 4),
                        round(c_lat, 4),
                    ],
                ),
                properties={
                    "risk_score": pred["dynamic_score"],
                    "risk_level": pred["final_risk"],
                    "static_class": pred["static_class"],
                    "dynamic_class": pred["dynamic_class"],
                    "model_version": pred["model_version"],
                },
            )

            features.append(feature)

    return GeoJSONFeatureCollection(
        type="FeatureCollection",
        features=features,
    )