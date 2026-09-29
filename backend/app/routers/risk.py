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

IoT integration:
- Latest ESP32 soil-moisture readings can be used by the
  existing Dynamic Trigger Random Forest.
- Five soil-moisture features are calculated from IoT history:
    soil_moisture
    soil_moisture_3d_mean
    soil_moisture_7d_mean
    soil_moisture_change_3d
    soil_moisture_change_7d
- MPU6050 acceleration/gyroscope values are stored but are NOT
  passed to the current Random Forest because the trained model
  was not trained with those features.

Earthquake integration:
- Recent earthquake activity is fetched from the USGS Earthquake Catalog.
- Four standardized earthquake features are generated:
    earthquake_present
    earthquake_magnitude
    earthquake_distance_km
    earthquake_age_hours
- Earthquake features are currently stored as prediction context only.
- They are NOT passed to the current Random Forest because the trained
  model was not trained with earthquake features.

GIS integration:
- Static GIS features are automatically extracted from the coordinate.
- Supported regions:
    Papum Pare
    West Kameng
- The GIS extractor supplies exactly the 10 static features expected
  by the trained Random Forest.
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from fastapi.encoders import jsonable_encoder

from geoalchemy2.elements import WKTElement

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db

from app.models.iot import (
    IoTSensorNode,
    IoTSensorReading,
)

from app.models.risk_prediction import (
    RiskPrediction,
    RiskLevel,
)

from app.services.alerting.evaluator import (
    process_risk_event,
)

from app.services.iot_features import (
    calculate_soil_moisture_features,
)

from app.services.live_data.open_meteo import (
    fetch_open_meteo,
    calculate_features,
)

from app.services.ml_service import ml_service

from app.services.earthquake_service import (
    get_recent_earthquakes,
)

from app.services.earthquake_features import (
    generate_earthquake_features,
)

from app.services.gis_features import (
    extract_static_gis_features,
)

from app.schemas.field_report import (
    GeoJSONFeatureCollection,
    GeoJSONFeature,
    GeoJSONGeometry,
)

from app.schemas.risk import RiskResponse


logger = logging.getLogger(__name__)


router = APIRouter(
    prefix="/risk",
    tags=["Landslide Risk"],
)


# ============================================================================
# HELPER 1
# FIND LATEST IOT READING NEAR A LOCATION
# ============================================================================

async def _get_latest_iot_reading_for_location(
    *,
    db: AsyncSession,
    lat: float,
    lon: float,
    radius_degrees: float = 0.05,
):
    """
    Find the latest IoT reading from an active sensor node
    near the requested coordinate.

    radius_degrees is a simple geographic approximation.

    This can later be replaced with a PostGIS ST_DWithin query.
    """

    min_lat = lat - radius_degrees
    max_lat = lat + radius_degrees

    min_lon = lon - radius_degrees
    max_lon = lon + radius_degrees

    result = await db.execute(
        select(
            IoTSensorReading,
            IoTSensorNode,
        )
        .join(
            IoTSensorNode,
            IoTSensorReading.node_id == IoTSensorNode.id,
        )
        .where(
            IoTSensorNode.is_active.is_(True),
            IoTSensorNode.latitude >= min_lat,
            IoTSensorNode.latitude <= max_lat,
            IoTSensorNode.longitude >= min_lon,
            IoTSensorNode.longitude <= max_lon,
        )
        .order_by(
            IoTSensorReading.observed_at.desc()
        )
        .limit(1)
    )

    row = result.first()

    if row is None:
        return None

    reading, node = row

    return {
        "reading": reading,
        "node": node,
    }


# ============================================================================
# HELPER 2
# CALCULATE IOT SOIL-MOISTURE FEATURES
# ============================================================================

async def _get_iot_soil_moisture_features(
    *,
    db: AsyncSession,
    lat: float,
    lon: float,
):
    """
    Get the latest nearby IoT soil-moisture reading and calculate
    the five soil-moisture features required by the existing
    Dynamic Trigger Random Forest.

    Returns None if no usable nearby soil-moisture reading exists.
    """

    latest = await _get_latest_iot_reading_for_location(
        db=db,
        lat=lat,
        lon=lon,
    )

    if latest is None:
        return None

    reading = latest["reading"]
    node = latest["node"]

    if reading.soil_moisture is None:
        return None

    soil_features = await calculate_soil_moisture_features(
        db=db,
        node_id=node.id,
        current_observed_at=reading.observed_at,
        current_soil_moisture=reading.soil_moisture,
    )

    return {
        **soil_features,
        "iot_node_id": node.node_id,
        "iot_observed_at": reading.observed_at,
    }


# ============================================================================
# HELPER 3
# GET RECENT EARTHQUAKE FEATURES
# ============================================================================

async def _get_earthquake_features(
    *,
    lat: float,
    lon: float,
):
    """
    Fetch recent nearby earthquakes from USGS and convert them
    into standardized earthquake features.

    Production query:
        radius = 200 km
        lookback = 72 hours
        minimum magnitude = 2.5

    These features are currently stored as context only.
    They are NOT passed to the existing Random Forest because
    the current model was not trained with earthquake features.
    """

    earthquake_data = await get_recent_earthquakes(
        latitude=lat,
        longitude=lon,
        radius_km=200.0,
        hours=72,
        min_magnitude=2.5,
    )

    earthquake_features = generate_earthquake_features(
        earthquake_data
    )

    return {
        "source": earthquake_data["source"],
        "query": earthquake_data["query"],
        "count": earthquake_data["count"],
        "features": earthquake_features,
        "strongest": earthquake_data["strongest"],
        "nearest": earthquake_data["nearest"],
        "fetched_at": earthquake_data["fetched_at"],
    }


# ============================================================================
# HELPER 4
# CONVERT ML RISK LABEL TO DATABASE/M5 RISK LEVEL
# ============================================================================

def _map_model_risk_to_backend_level(
    model_risk: str,
) -> RiskLevel:
    """
    Convert the ML model's risk terminology into the existing
    GeoNex database/M5 RiskLevel terminology.

    ML model output:
        LOW
        MODERATE
        HIGH
        VERY HIGH

    Database/M5 output:
        LOW
        WATCH
        WARNING
        CRITICAL
    """

    mapping = {
        "LOW": RiskLevel.LOW,
        "MODERATE": RiskLevel.WATCH,
        "HIGH": RiskLevel.WARNING,
        "VERY HIGH": RiskLevel.CRITICAL,
    }

    normalized_risk = str(model_risk).strip().upper()

    if normalized_risk not in mapping:
        raise ValueError(
            f"Unknown ML risk level: {model_risk!r}. "
            f"Expected one of: {', '.join(mapping.keys())}"
        )

    return mapping[normalized_risk]


# ============================================================================
# HELPER 5
# SAVE M1 PREDICTION + TRIGGER M5
# ============================================================================

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

    The prediction is committed BEFORE M5 is called.

    This guarantees that M5 can read the committed RiskPrediction.
    """

    risk_level = _map_model_risk_to_backend_level(
        prediction["final_risk"]
    )

    json_safe_feature_snapshot = jsonable_encoder(
        feature_snapshot
    )

    risk_prediction = RiskPrediction(
        location=WKTElement(
            f"POINT({lon} {lat})",
            srid=4326,
        ),
        latitude=lat,
        longitude=lon,
        risk_score=float(
            prediction["dynamic_score"]
        ),
        risk_level=risk_level,
        confidence=float(
            prediction.get("confidence", 0.0)
        ),
        model_version=prediction["model_version"],
        feature_snapshot=json_safe_feature_snapshot,
        created_at=datetime.now(timezone.utc),
    )

    db.add(risk_prediction)

    await db.commit()

    await db.refresh(risk_prediction)

    logger.info(
        "M1 prediction saved: "
        "prediction_id=%s risk_level=%s risk_score=%s "
        "lat=%s lon=%s",
        risk_prediction.id,
        risk_prediction.risk_level,
        risk_prediction.risk_score,
        lat,
        lon,
    )

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

        await db.rollback()

        logger.exception(
            "M5 Alert Engine failed for prediction_id=%s. "
            "Prediction remains stored and can be reconciled later.",
            risk_prediction.id,
        )

    return risk_prediction


# ============================================================================
# GET /risk/location
# ============================================================================

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

    # ------------------------------------------------------------------------
    # SOIL-MOISTURE FALLBACK VALUES
    # ------------------------------------------------------------------------

    soil_moisture: float = Query(
        0.42,
        description="Fallback soil moisture when no nearby IoT sensor is available",
    ),

    soil_moisture_3d_mean: float = Query(
        0.40,
        description="Fallback 3-day soil moisture mean",
    ),

    soil_moisture_7d_mean: float = Query(
        0.38,
        description="Fallback 7-day soil moisture mean",
    ),

    soil_moisture_change_3d: float = Query(
        0.02,
        description="Fallback 3-day soil moisture change",
    ),

    soil_moisture_change_7d: float = Query(
        0.04,
        description="Fallback 7-day soil moisture change",
    ),

    db: AsyncSession = Depends(get_db),
):
    """
    Get AI landslide risk prediction for a specific coordinate.

    Static GIS features are extracted automatically.

    Flow:

        Coordinate
             ↓
        GIS feature extraction
             ↓
        Open-Meteo rainfall
             ↓
        Nearby IoT sensor
             ↓
        Soil-moisture features
             ↓
        USGS earthquake context
             ↓
        M1 Random Forest
             ↓
        risk_predictions
             ↓
        M5 Alert Engine
    """

    # ========================================================================
    # 1. AUTOMATIC STATIC GIS FEATURES
    # ========================================================================

    try:
        static_features = extract_static_gis_features(
            latitude=lat,
            longitude=lon,
        )

    except ValueError as exc:
        logger.warning(
            "GIS coverage error for lat=%s lon=%s: %s",
            lat,
            lon,
            exc,
        )

        from fastapi import HTTPException

        raise HTTPException(
            status_code=400,
            detail=str(exc),
        ) from exc

    except FileNotFoundError as exc:
        logger.exception(
            "Required GIS file is missing."
        )

        from fastapi import HTTPException

        raise HTTPException(
            status_code=500,
            detail=f"GIS configuration error: {exc}",
        ) from exc

    except Exception as exc:
        logger.exception(
            "Unexpected GIS feature extraction error."
        )

        from fastapi import HTTPException

        raise HTTPException(
            status_code=500,
            detail="Failed to extract static GIS features.",
        ) from exc

    # The extractor includes region for metadata, but the trained
    # Random Forest expects exactly the 10 model features.
    gis_region = static_features.pop(
        "region",
        None,
    )

    logger.info(
        "Automatic GIS features loaded: "
        "region=%s lat=%s lon=%s",
        gis_region,
        lat,
        lon,
    )

    # ========================================================================
    # 2. FETCH RAINFALL AUTOMATICALLY FROM OPEN-METEO
    # ========================================================================

    live_data = await fetch_open_meteo(
        lat,
        lon,
    )

    rainfall_features = calculate_features(
        live_data
    )

    dynamic_features = {
        "rainfall_1d": rainfall_features.get("rainfall_1d"),
        "rainfall_3d": rainfall_features.get("rainfall_3d"),
        "rainfall_7d": rainfall_features.get("rainfall_7d"),
        "rainfall_14d": rainfall_features.get("rainfall_14d"),
        "rainfall_30d": rainfall_features.get("rainfall_30d"),
        "rainfall_max_3d": rainfall_features.get("rainfall_max_3d"),
        "rainfall_max_7d": rainfall_features.get("rainfall_max_7d"),
        "rainy_days_7d": rainfall_features.get("rainy_days_7d"),
        "rainy_days_14d": rainfall_features.get("rainy_days_14d"),
        "rainy_days_30d": rainfall_features.get("rainy_days_30d"),

        # Fallback soil-moisture values.
        "soil_moisture": soil_moisture,
        "soil_moisture_3d_mean": soil_moisture_3d_mean,
        "soil_moisture_7d_mean": soil_moisture_7d_mean,
        "soil_moisture_change_3d": soil_moisture_change_3d,
        "soil_moisture_change_7d": soil_moisture_change_7d,
    }

    logger.info(
        "Open-Meteo rainfall features loaded for "
        "lat=%s lon=%s: %s",
        lat,
        lon,
        {
            key: value
            for key, value in dynamic_features.items()
            if key.startswith("rainfall_")
            or key.startswith("rainy_days_")
        },
    )

    # ========================================================================
    # 3. TRY TO USE NEARBY IOT SENSOR
    # ========================================================================

    iot_features = await _get_iot_soil_moisture_features(
        db=db,
        lat=lat,
        lon=lon,
    )

    iot_used = False
    iot_node_id = None
    iot_observed_at = None

    if iot_features is not None:

        dynamic_features["soil_moisture"] = (
            iot_features["soil_moisture"]
        )

        if iot_features["soil_moisture_3d_mean"] is not None:
            dynamic_features["soil_moisture_3d_mean"] = (
                iot_features["soil_moisture_3d_mean"]
            )

        if iot_features["soil_moisture_7d_mean"] is not None:
            dynamic_features["soil_moisture_7d_mean"] = (
                iot_features["soil_moisture_7d_mean"]
            )

        if iot_features["soil_moisture_change_3d"] is not None:
            dynamic_features["soil_moisture_change_3d"] = (
                iot_features["soil_moisture_change_3d"]
            )

        if iot_features["soil_moisture_change_7d"] is not None:
            dynamic_features["soil_moisture_change_7d"] = (
                iot_features["soil_moisture_change_7d"]
            )

        iot_used = True

        iot_node_id = iot_features["iot_node_id"]
        iot_observed_at = iot_features["iot_observed_at"]

        logger.info(
            "Using IoT soil-moisture data for risk prediction: "
            "node_id=%s observed_at=%s",
            iot_node_id,
            iot_observed_at,
        )

    else:

        logger.info(
            "No nearby IoT soil-moisture reading found for "
            "lat=%s lon=%s. Using request/default soil-moisture values.",
            lat,
            lon,
        )

    # ========================================================================
    # 4. EARTHQUAKE CONTEXT
    # ========================================================================

    earthquake_context = await _get_earthquake_features(
        lat=lat,
        lon=lon,
    )

    logger.info(
        "Earthquake context for risk/location: "
        "present=%s magnitude=%s distance_km=%s age_hours=%s",
        earthquake_context["features"]["earthquake_present"],
        earthquake_context["features"]["earthquake_magnitude"],
        earthquake_context["features"]["earthquake_distance_km"],
        earthquake_context["features"]["earthquake_age_hours"],
    )

    # ========================================================================
    # 5. M1 PREDICTION
    # ========================================================================

    prediction = await ml_service.predict_risk(
        {
            "static_features": static_features,
            "dynamic_features": dynamic_features,
        }
    )

    # ========================================================================
    # 6. FEATURE SNAPSHOT
    # ========================================================================

    feature_snapshot = {
        "static": static_features,
        "dynamic": dynamic_features,
        "gis_region": gis_region,
        "rainfall_source": "Open-Meteo",
        "earthquake": earthquake_context,
        "static_score": prediction["static_score"],
        "static_class": prediction["static_class"],
        "dynamic_score": prediction["dynamic_score"],
        "dynamic_class": prediction["dynamic_class"],
        "final_risk": prediction["final_risk"],
        "iot": {
            "used": iot_used,
            "node_id": iot_node_id,
            "observed_at": iot_observed_at,
        },
    }

    # ========================================================================
    # 7. CONVERT ML RISK TO BACKEND RISK
    # ========================================================================

    backend_risk_level = _map_model_risk_to_backend_level(
        prediction["final_risk"]
    )

    # ========================================================================
    # 8. SAVE + TRIGGER M5
    # ========================================================================

    await _save_and_process_prediction(
        db=db,
        lat=lat,
        lon=lon,
        prediction=prediction,
        feature_snapshot=feature_snapshot,
    )

    # ========================================================================
    # 9. RETURN RESPONSE
    # ========================================================================

    return RiskResponse(
        latitude=lat,
        longitude=lon,
        risk_score=prediction["dynamic_score"],
        risk_level=backend_risk_level,
        confidence=prediction.get(
            "confidence",
            0.0,
        ),
        model_version=prediction["model_version"],
        feature_snapshot=jsonable_encoder(
            feature_snapshot
        ),
        timestamp=datetime.now(timezone.utc),
    )


# ============================================================================
# GET /risk/live
# ============================================================================

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
    Get landslide risk using:

        Automatic GIS static features
              +
        Open-Meteo rainfall
              +
        latest nearby IoT soil moisture
              +
        USGS earthquake context
              ↓
        M1 ML model
              ↓
        risk_predictions
              ↓
        M5 Alert Engine
    """

    # ========================================================================
    # 1. AUTOMATIC STATIC GIS FEATURES
    # ========================================================================

    try:
        static_features = extract_static_gis_features(
            latitude=lat,
            longitude=lon,
        )

    except ValueError as exc:
        from fastapi import HTTPException

        raise HTTPException(
            status_code=400,
            detail=str(exc),
        ) from exc

    except FileNotFoundError as exc:
        logger.exception(
            "Required GIS file is missing."
        )

        from fastapi import HTTPException

        raise HTTPException(
            status_code=500,
            detail=f"GIS configuration error: {exc}",
        ) from exc

    except Exception as exc:
        logger.exception(
            "Unexpected GIS feature extraction error."
        )

        from fastapi import HTTPException

        raise HTTPException(
            status_code=500,
            detail="Failed to extract static GIS features.",
        ) from exc

    gis_region = static_features.pop(
        "region",
        None,
    )

    # ========================================================================
    # 2. FETCH LIVE OPEN-METEO DATA
    # ========================================================================

    live_data = await fetch_open_meteo(
        lat,
        lon,
    )

    dynamic_features = calculate_features(
        live_data
    )

    live_data_timestamp = dynamic_features.get(
        "last_observation"
    )

    fetched_at = dynamic_features.get(
        "fetched_at"
    )

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

    # ========================================================================
    # 3. ADD IOT SOIL-MOISTURE FEATURES
    # ========================================================================

    iot_features = await _get_iot_soil_moisture_features(
        db=db,
        lat=lat,
        lon=lon,
    )

    iot_used = False
    iot_node_id = None
    iot_observed_at = None

    if iot_features is not None:

        dynamic_features["soil_moisture"] = (
            iot_features["soil_moisture"]
        )

        if iot_features["soil_moisture_3d_mean"] is not None:
            dynamic_features["soil_moisture_3d_mean"] = (
                iot_features["soil_moisture_3d_mean"]
            )

        if iot_features["soil_moisture_7d_mean"] is not None:
            dynamic_features["soil_moisture_7d_mean"] = (
                iot_features["soil_moisture_7d_mean"]
            )

        if iot_features["soil_moisture_change_3d"] is not None:
            dynamic_features["soil_moisture_change_3d"] = (
                iot_features["soil_moisture_change_3d"]
            )

        if iot_features["soil_moisture_change_7d"] is not None:
            dynamic_features["soil_moisture_change_7d"] = (
                iot_features["soil_moisture_change_7d"]
            )

        iot_used = True

        iot_node_id = iot_features["iot_node_id"]
        iot_observed_at = iot_features["iot_observed_at"]

    # ========================================================================
    # 4. EARTHQUAKE CONTEXT
    # ========================================================================

    earthquake_context = await _get_earthquake_features(
        lat=lat,
        lon=lon,
    )

    # ========================================================================
    # 5. M1 PREDICTION
    # ========================================================================

    prediction = await ml_service.predict_risk(
        {
            "static_features": static_features,
            "dynamic_features": dynamic_features,
        }
    )

    # ========================================================================
    # 6. FEATURE SNAPSHOT
    # ========================================================================

    feature_snapshot = {
        "static": static_features,
        "dynamic": dynamic_features,
        "gis_region": gis_region,
        "earthquake": earthquake_context,
        "static_score": prediction["static_score"],
        "static_class": prediction["static_class"],
        "dynamic_score": prediction["dynamic_score"],
        "dynamic_class": prediction["dynamic_class"],
        "final_risk": prediction["final_risk"],
        "live_source": "Open-Meteo",
        "live_data_timestamp": live_data_timestamp,
        "fetched_at": fetched_at,
        "iot": {
            "used": iot_used,
            "node_id": iot_node_id,
            "observed_at": iot_observed_at,
        },
    }

    # ========================================================================
    # 7. CONVERT ML RISK TO BACKEND RISK
    # ========================================================================

    backend_risk_level = _map_model_risk_to_backend_level(
        prediction["final_risk"]
    )

    # ========================================================================
    # 8. SAVE + TRIGGER M5
    # ========================================================================

    await _save_and_process_prediction(
        db=db,
        lat=lat,
        lon=lon,
        prediction=prediction,
        feature_snapshot=feature_snapshot,
    )

    # ========================================================================
    # 9. RETURN RESPONSE
    # ========================================================================

    return RiskResponse(
        latitude=lat,
        longitude=lon,
        risk_score=prediction["dynamic_score"],
        risk_level=backend_risk_level,
        confidence=prediction.get(
            "confidence",
            0.0,
        ),
        model_version=prediction["model_version"],
        feature_snapshot=jsonable_encoder(
            feature_snapshot
        ),
        timestamp=datetime.now(timezone.utc),
    )


# ============================================================================
# GET /risk/area
# ============================================================================

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

    The area endpoint remains a simulated grid and therefore
    does not use automatic GIS extraction.
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