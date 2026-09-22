from ml.inference import predict_risk


# ============================================================
# STATIC FEATURES
# Representative West Kameng location
# ============================================================

static_features = {
    "elevation": 2324.055,
    "slope": 28.192,
    "curvature": -2.0,
    "soil_type": 7,
    "ndvi_2017": 0.5495,
    "distance_to_river_m": 1618.0,
    "distance_to_road_m": 2334.99,
    "distance_to_village_m": 3375.0,
    "aspect_sin": 0.0,
    "aspect_cos": 0.0,
}


# ============================================================
# DYNAMIC FEATURES
# 2026-06-30 — latest complete dynamic input
# ============================================================

dynamic_features = {
    "rainfall_1d": 4.419027659881633,
    "rainfall_3d": 14.338463000732208,
    "rainfall_7d": 24.64092325293557,
    "rainfall_14d": 39.83474951383248,
    "rainfall_30d": 138.31372546622583,
    "rainfall_max_3d": 8.802929813151472,
    "rainfall_max_7d": 8.802929813151472,
    "rainy_days_7d": 5,
    "rainy_days_14d": 10,
    "rainy_days_30d": 22,
    "soil_moisture": 34.90905703873506,
    "soil_moisture_3d_mean": 34.86206042273705,
    "soil_moisture_7d_mean": 33.936055712873134,
    "soil_moisture_change_3d": 1.3170250695024637,
    "soil_moisture_change_7d": 0.5885437511546527,
}


# ============================================================
# RUN PREDICTION
# ============================================================

result = predict_risk(
    static_features,
    dynamic_features,
)


# ============================================================
# DISPLAY RESULT
# ============================================================

print("\n" + "=" * 50)
print("LANDSLIDE RISK INFERENCE TEST")
print("=" * 50)

print(f"Static score:   {result['static_score']:.6f}")
print(f"Static class:   {result['static_class']}")

print(f"Dynamic score:  {result['dynamic_score']:.6f}")
print(f"Dynamic class:  {result['dynamic_class']}")

print(f"Final risk:     {result['final_risk']}")

print("=" * 50)
print("INFERENCE TEST: PASS")
print("=" * 50)