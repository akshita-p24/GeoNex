from pathlib import Path
import json

import joblib
import pandas as pd


# ============================================================
# PATHS
# ============================================================

ML_DIR = Path(__file__).resolve().parent
ML_PACKAGE_DIR = ML_DIR / "ml"

MODELS_DIR = ML_PACKAGE_DIR / "models"
METADATA_DIR = ML_PACKAGE_DIR / "metadata"
RISK_DIR = ML_PACKAGE_DIR / "risk"


STATIC_MODEL_PATH = (
    MODELS_DIR / "final_landslide_random_forest_pipeline.pkl"
)

DYNAMIC_MODEL_PATH = (
    MODELS_DIR / "final_dynamic_trigger_random_forest_pipeline.pkl"
)

STATIC_METADATA_PATH = (
    METADATA_DIR / "final_landslide_model_metadata.json"
)

DYNAMIC_METADATA_PATH = (
    METADATA_DIR / "final_dynamic_trigger_model_metadata.json"
)

RISK_CONFIG_PATH = (
    RISK_DIR / "step9b_risk_integration_config.json"
)


# ============================================================
# LOAD MODELS
# ============================================================

print("Loading landslide ML models...")

static_model = joblib.load(STATIC_MODEL_PATH)
dynamic_model = joblib.load(DYNAMIC_MODEL_PATH)

print("Static model loaded")
print("Dynamic model loaded")


# ============================================================
# LOAD METADATA
# ============================================================

with open(STATIC_METADATA_PATH, "r") as f:
    static_metadata = json.load(f)

with open(DYNAMIC_METADATA_PATH, "r") as f:
    dynamic_metadata = json.load(f)

with open(RISK_CONFIG_PATH, "r") as f:
    risk_config = json.load(f)


# ============================================================
# FEATURE SCHEMAS
# ============================================================

STATIC_FEATURES = [
    "elevation",
    "slope",
    "curvature",
    "soil_type",
    "ndvi_2017",
    "distance_to_river_m",
    "distance_to_road_m",
    "distance_to_village_m",
    "aspect_sin",
    "aspect_cos",
]

DYNAMIC_FEATURES = [
    "rainfall_1d",
    "rainfall_3d",
    "rainfall_7d",
    "rainfall_14d",
    "rainfall_30d",
    "rainfall_max_3d",
    "rainfall_max_7d",
    "rainy_days_7d",
    "rainy_days_14d",
    "rainy_days_30d",
    "soil_moisture",
    "soil_moisture_3d_mean",
    "soil_moisture_7d_mean",
    "soil_moisture_change_3d",
    "soil_moisture_change_7d",
]


# ============================================================
# THRESHOLDS
# ============================================================

STATIC_THRESHOLDS = {
    "LOW": 0.25,
    "MODERATE": 0.50,
    "HIGH": 0.75,
}

DYNAMIC_THRESHOLDS = {
    "LOW": 0.13,
    "MODERATE": 0.30,
    "HIGH": 0.50,
}


# ============================================================
# CLASSIFICATION
# ============================================================

def classify_static(score: float) -> str:

    if score < 0.25:
        return "LOW"

    if score < 0.50:
        return "MODERATE"

    if score < 0.75:
        return "HIGH"

    return "VERY HIGH"


def classify_dynamic(score: float) -> str:

    if score < 0.13:
        return "LOW"

    if score < 0.30:
        return "MODERATE"

    if score < 0.50:
        return "HIGH"

    return "VERY HIGH"


# ============================================================
# RISK MATRIX
# ============================================================

RISK_MATRIX = {
    "LOW": {
        "LOW": "LOW",
        "MODERATE": "LOW",
        "HIGH": "MODERATE",
        "VERY HIGH": "HIGH",
    },

    "MODERATE": {
        "LOW": "LOW",
        "MODERATE": "MODERATE",
        "HIGH": "HIGH",
        "VERY HIGH": "HIGH",
    },

    "HIGH": {
        "LOW": "MODERATE",
        "MODERATE": "HIGH",
        "HIGH": "HIGH",
        "VERY HIGH": "VERY HIGH",
    },

    "VERY HIGH": {
        "LOW": "HIGH",
        "MODERATE": "HIGH",
        "HIGH": "VERY HIGH",
        "VERY HIGH": "VERY HIGH",
    },
}


# ============================================================
# STATIC PREDICTION
# ============================================================

def predict_static(features: dict) -> dict:

    missing = [
        feature
        for feature in STATIC_FEATURES
        if feature not in features
    ]

    if missing:
        raise ValueError(
            f"Missing static features: {missing}"
        )

    df = pd.DataFrame(
        [[features[feature] for feature in STATIC_FEATURES]],
        columns=STATIC_FEATURES,
    )

    score = float(
        static_model.predict_proba(df)[0][1]
    )

    risk_class = classify_static(score)

    return {
        "static_score": score,
        "static_class": risk_class,
    }


# ============================================================
# DYNAMIC PREDICTION
# ============================================================

def predict_dynamic(features: dict) -> dict:

    missing = [
        feature
        for feature in DYNAMIC_FEATURES
        if feature not in features
    ]

    if missing:
        raise ValueError(
            f"Missing dynamic features: {missing}"
        )

    df = pd.DataFrame(
        [[features[feature] for feature in DYNAMIC_FEATURES]],
        columns=DYNAMIC_FEATURES,
    )

    score = float(
        dynamic_model.predict_proba(df)[0][1]
    )

    risk_class = classify_dynamic(score)

    return {
        "dynamic_score": score,
        "dynamic_class": risk_class,
    }


# ============================================================
# FINAL RISK
# ============================================================

def calculate_final_risk(
    static_class: str,
    dynamic_class: str,
) -> str:

    return RISK_MATRIX[static_class][dynamic_class]


# ============================================================
# COMPLETE PREDICTION
# ============================================================

def predict_risk(
    static_features: dict,
    dynamic_features: dict,
) -> dict:

    static_result = predict_static(static_features)

    dynamic_result = predict_dynamic(dynamic_features)

    final_risk = calculate_final_risk(
        static_result["static_class"],
        dynamic_result["dynamic_class"],
    )

    return {
        **static_result,
        **dynamic_result,
        "final_risk": final_risk,
    }