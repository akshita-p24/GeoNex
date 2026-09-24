"""
Risk Prediction API Endpoints.

M1 ML integration:
- GET /api/v1/risk/location
- GET /api/v1/risk/live
- GET /api/v1/risk/area

M5 Alert Engine integration:
- M1 prediction is persisted to risk_predictions.
- The committed prediction is then passed to M5.
- M5 evaluates the prediction and creates/updates alerts.
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from geoalchemy2.elements import WKTElement

from app.core.database import get_db
from app.models.risk_prediction import RiskPrediction, RiskLevel
from app.services.ml_service import ml_service
from app.services.alerting.evaluator import process_risk_event

from app.services.live_data.open_meteo import (
    fetch_open_meteo,
    calculate_features,
)

from app.schemas.risk import RiskResponse
from app.schemas.field_report import (
    GeoJSONFeatureCollection,
    GeoJSONFeature,
    GeoJSONGeometry,
)

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/risk",
    tags=["Landslide Risk"],
)


# ---------------------------------------------------------------------------
# Helper: save M1 prediction and trigger M5 Alert Engine
# ---------------------------------------------------------------------------

async def _save_and_process_prediction(
    *,
    db: AsyncSession,
    lat: float,
    lon: float,
    prediction: dict,
    feature_snapshot: dict,
) -> RiskPrediction:
    """
    Save an M1 prediction into risk_predictions.

    IMPORTANT:
    The prediction is committed BEFORE M5 is called.

    This guarantees that M5's read-only RiskPredictionRepository
    can see the committed prediction.
    """

    risk_level = RiskLevel(prediction["final_risk"])

    risk_prediction = RiskPrediction(
        location=WKTElement(
            f"POINT({lon} {lat})",
            srid=4326,
        ),
        latitude=lat,
        longitude=lon,
        risk_score=float(prediction["dynamic_score"]),
        risk_level=risk_level,
        confidence=float(
            prediction.get("confidence", 0.0)
        ),
        model_version=prediction["model_version"],
        feature_snapshot=feature_snapshot,
        created_at=datetime.now(timezone.utc),
    )

    # ---------------------------------------------------------
    # 1. Save prediction
    # ---------------------------------------------------------

    db.add(risk_prediction)

    await db.commit()
    await db.refresh(risk_prediction)

    logger.info(
        "M1 prediction saved: prediction_id=%s risk_level=%s "
        "risk_score=%s lat=%s lon=%s",
        risk_prediction.id,
        risk_prediction.risk_level,
        risk_prediction.risk_score,
        lat,
        lon,
    )

    # ---------------------------------------------------------
    # 2. Trigger M5 Alert Engine
    # ---------------------------------------------------------

    try:
        await process_risk_event(
            risk_prediction.id,
            db,
        )

        await db.commit()

        logger.info(
            "M5 Alert Engine processed prediction_id=%s",
            risk_prediction.id,
        )

    except Exception:
        # The prediction itself is already committed.
        # Roll back only the failed M5 transaction.
        await db.rollback()

        logger.exception(
            "M5 Alert Engine failed for prediction_id=%s. "
            "Prediction remains stored and can be reconciled later.",
            risk_prediction.id,
        )

    return risk_prediction


# ---------------------------------------------------------------------------
# GET /risk/location
# ---------------------------------------------------------------------------

@router.get(
    "/location",
    response_model=RiskResponse,
)
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

    # STATIC FEATURES
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

    # DYNAMIC FEATURES
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

    db: AsyncSession = Depends(get_db),
):
    """
    Get AI landslide risk prediction for a specific coordinate.

    The prediction is:
        1. Generated by M1.
        2. Stored in risk_predictions.
        3. Committed.
        4. Sent to the M5 Alert Engine.
    """

    # ---------------------------------------------------------
    # 1. STATIC FEATURES
    # ---------------------------------------------------------

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

    # ---------------------------------------------------------
    # 2. DYNAMIC FEATURES
    # ---------------------------------------------------------

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

    # ---------------------------------------------------------
    # 3. M1 PREDICTION
    # ---------------------------------------------------------

    prediction = await ml_service.predict_risk(
        {
            "static_features": static_features,
            "dynamic_features": dynamic_features,
        }
    )

    # ---------------------------------------------------------
    # 4. FEATURE SNAPSHOT
    # ---------------------------------------------------------

    feature_snapshot = {
        "static": static_features,
        "dynamic": dynamic_features,
        "static_score": prediction["static_score"],
        "static_class": prediction["static_class"],
        "dynamic_score": prediction["dynamic_score"],
        "dynamic_class": prediction["dynamic_class"],
        "final_risk": prediction["final_risk"],
    }

    # ---------------------------------------------------------
    # 5. SAVE + TRIGGER M5
    # ---------------------------------------------------------

    await _save_and_process_prediction(
        db=db,
        lat=lat,
        lon=lon,
        prediction=prediction,
        feature_snapshot=feature_snapshot,
    )

    # ---------------------------------------------------------
    # 6. RETURN RESPONSE
    # ---------------------------------------------------------

    return RiskResponse(
        latitude=lat,
        longitude=lon,
        risk_score=prediction["dynamic_score"],
        risk_level=prediction["final_risk"],
        confidence=prediction.get("confidence", 0.0),
        model_version=prediction["model_version"],
        feature_snapshot=feature_snapshot,
        timestamp=datetime.now(timezone.utc),
    )


# ---------------------------------------------------------------------------
# GET /risk/live
# ---------------------------------------------------------------------------

@router.get(
    "/live",
    response_model=RiskResponse,
)
async def get_live_risk(
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
    db: AsyncSession = Depends(get_db),
):
    """
    Get landslide risk using live Open-Meteo dynamic data.

    Flow:

        Open-Meteo
             ↓
        M1 ML model
             ↓
        risk_predictions
             ↓
        M5 Alert Engine
    """

    # ---------------------------------------------------------
    # 1. FETCH LIVE OPEN-METEO DATA
    # ---------------------------------------------------------

    live_data = await fetch_open_meteo(
        lat,
        lon,
    )

    # ---------------------------------------------------------
    # 2. CALCULATE M1 DYNAMIC FEATURES
    # ---------------------------------------------------------

    dynamic_features = calculate_features(
        live_data
    )

    live_data_timestamp = dynamic_features.get(
        "last_observation"
    )

    fetched_at = dynamic_features.get(
        "fetched_at"
    )

    # Keep only M1 features.
    dynamic_features = {
        key: value
        for key, value in dynamic_features.items()
        if key not in {
            "latitude",
            "longitude",
            "timezone",
            "last_observation",
            "fetched_at",
        }
    }

    # ---------------------------------------------------------
    # 3. STATIC FEATURES
    # ---------------------------------------------------------

    # Temporary defaults.
    # These can later be replaced with real GIS/PostGIS data.

    static_features = {
        "elevation": 500.0,
        "slope": 25.0,
        "curvature": 0.0,
        "soil_type": 1.0,
        "ndvi_2017": 0.5,
        "distance_to_river_m": 1000.0,
        "distance_to_road_m": 1000.0,
        "distance_to_village_m": 2000.0,
        "aspect_sin": 0.0,
        "aspect_cos": 1.0,
    }

    # ---------------------------------------------------------
    # 4. M1 PREDICTION
    # ---------------------------------------------------------

    prediction = await ml_service.predict_risk(
        {
            "static_features": static_features,
            "dynamic_features": dynamic_features,
        }
    )

    # ---------------------------------------------------------
    # 5. FEATURE SNAPSHOT
    # ---------------------------------------------------------

    feature_snapshot = {
        "static": static_features,
        "dynamic": dynamic_features,
        "static_score": prediction["static_score"],
        "static_class": prediction["static_class"],
        "dynamic_score": prediction["dynamic_score"],
        "dynamic_class": prediction["dynamic_class"],
        "final_risk": prediction["final_risk"],
        "live_source": "Open-Meteo",
        "live_data_timestamp": live_data_timestamp,
        "fetched_at": fetched_at,
    }

    # ---------------------------------------------------------
    # 6. SAVE + TRIGGER M5
    # ---------------------------------------------------------

    await _save_and_process_prediction(
        db=db,
        lat=lat,
        lon=lon,
        prediction=prediction,
        feature_snapshot=feature_snapshot,
    )

    # ---------------------------------------------------------
    # 7. RETURN RESPONSE
    # ---------------------------------------------------------

    return RiskResponse(
        latitude=lat,
        longitude=lon,
        risk_score=prediction["dynamic_score"],
        risk_level=prediction["final_risk"],
        confidence=prediction.get("confidence", 0.0),
        model_version=prediction["model_version"],
        feature_snapshot=feature_snapshot,
        timestamp=datetime.now(timezone.utc),
    )


# ---------------------------------------------------------------------------
# GET /risk/area
# ---------------------------------------------------------------------------

@router.get(
    "/area",
    response_model=GeoJSONFeatureCollection,
)
async def get_risk_area(
    min_lat: float = Query(26.0),
    max_lat: float = Query(28.0),
    min_lon: float = Query(91.0),
    max_lon: float = Query(94.0),
):
    """
    Return a simulated GeoJSON risk grid.

    These are display/grid predictions only.

    They are intentionally NOT stored in risk_predictions
    and are NOT sent to the M5 Alert Engine.
    """

    features = []

    lat_steps = 3
    lon_steps = 3

    lat_delta = (
        max_lat - min_lat
    ) / lat_steps

    lon_delta = (
        max_lon - min_lon
    ) / lon_steps

    for i in range(lat_steps):
        for j in range(lon_steps):

            c_lat = (
                min_lat
                + (i + 0.5) * lat_delta
            )

            c_lon = (
                min_lon
                + (j + 0.5) * lon_delta
            )

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