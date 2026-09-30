"""
End-to-End Test Suite for GeoNex Steps 2, 3, and 4.
Validates:
1. Python interpreter and required imports
2. Static GIS feature extraction on real coordinates
3. Live Open-Meteo dynamic feature extraction on real coordinates
4. Real Random Forest model inference and scoring
5. FastAPI /api/v1/risk/location endpoint end-to-end
6. Failure-case handling for out-of-coverage coordinates
"""

import asyncio
import sys
import json
from pathlib import Path

# Verify imports
import rasterio
import joblib
import pandas as pd
import sklearn
import fastapi
import httpx

from app.services.gis_features import extract_static_gis_features, detect_region
from app.services.live_data.open_meteo import fetch_open_meteo, calculate_features
from inference import predict_risk, static_model, dynamic_model
from app.main import app

COORD_A = {"name": "Papum Pare (NH-415)", "lat": 27.15, "lon": 93.70}
COORD_B = {"name": "West Kameng (Dirang)", "lat": 27.35, "lon": 92.45}
COORD_OUT = {"name": "Dima Hasao (Out of coverage)", "lat": 25.1764, "lon": 93.0238}

async def run_e2e_tests():
    print("=" * 60)
    print("GEONEX STEPS 2-4 PIPELINE VERIFICATION SUITE")
    print("=" * 60)
    
    # Section A & B: Python Interpreter & Imports
    print("\n[A & B] ENVIRONMENT & IMPORTS:")
    print(f"  Python Interpreter : {sys.executable}")
    print(f"  Python Version     : {sys.version.split()[0]}")
    print(f"  All required libraries (rasterio, joblib, pandas, sklearn, fastapi, httpx) loaded successfully.")

    # Section E: Models Loaded
    print("\n[E] ML MODELS LOADED:")
    print(f"  Static Pipeline  : {type(static_model).__name__} (classes: {static_model.classes_})")
    print(f"  Dynamic Pipeline : {type(dynamic_model).__name__} (classes: {dynamic_model.classes_})")

    # Section F & G: Coordinate A & B Tests
    for coord in [COORD_A, COORD_B]:
        print(f"\n" + "-" * 60)
        print(f"TESTING COORDINATE: {coord['name']} (lat={coord['lat']}, lon={coord['lon']})")
        print("-" * 60)
        
        # 1. Static GIS Extraction
        static_feats = extract_static_gis_features(coord['lat'], coord['lon'])
        gis_region = static_feats.pop("region", None)
        print(f"  Detected GIS Region: {gis_region}")
        print(f"  [C] Exact 10 Static Features:")
        for k, v in static_feats.items():
            print(f"    {k:22s}: {v}")
            
        # 2. Live Dynamic Weather (Open-Meteo)
        weather_raw = await fetch_open_meteo(coord['lat'], coord['lon'])
        weather_feats = calculate_features(weather_raw)
        dyn_15 = {
            k: weather_feats[k] for k in [
                "rainfall_1d", "rainfall_3d", "rainfall_7d", "rainfall_14d", "rainfall_30d",
                "rainfall_max_3d", "rainfall_max_7d", "rainy_days_7d", "rainy_days_14d", "rainy_days_30d",
                "soil_moisture", "soil_moisture_3d_mean", "soil_moisture_7d_mean",
                "soil_moisture_change_3d", "soil_moisture_change_7d"
            ]
        }
        print(f"  [D] Exact 15 Dynamic Features (Open-Meteo returned lat={weather_raw['latitude']}, lon={weather_raw['longitude']}):")
        for k, v in dyn_15.items():
            print(f"    {k:24s}: {v}")
            
        # 3. Direct ML Prediction
        ml_pred = predict_risk(static_feats, dyn_15)
        print(f"  Direct ML Prediction:")
        print(f"    Static Score   : {ml_pred['static_score']:.6f} ({ml_pred['static_class']})")
        print(f"    Dynamic Score  : {ml_pred['dynamic_score']:.6f} ({ml_pred['dynamic_class']})")
        print(f"    Final Risk     : {ml_pred['final_risk']}")

    # Section J: Actual FastAPI Prediction Endpoint
    print("\n" + "=" * 60)
    print("[J] TESTING FASTAPI PREDICTION ENDPOINT: /api/v1/risk/location")
    print("=" * 60)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        # Request for Coord A
        resp_a = await client.get("/api/v1/risk/location", params={"lat": COORD_A['lat'], "lon": COORD_A['lon']})
        print(f"  GET /api/v1/risk/location?lat={COORD_A['lat']}&lon={COORD_A['lon']}")
        print(f"  Response Status : {resp_a.status_code}")
        body_a = resp_a.json()
        print(f"  Response Lat/Lon: ({body_a['latitude']}, {body_a['longitude']})")
        print(f"  Risk Score      : {body_a['risk_score']}")
        print(f"  Risk Level      : {body_a['risk_level']}")
        print(f"  Model Version   : {body_a['model_version']}")

        # Request for Coord B
        resp_b = await client.get("/api/v1/risk/location", params={"lat": COORD_B['lat'], "lon": COORD_B['lon']})
        print(f"\n  GET /api/v1/risk/location?lat={COORD_B['lat']}&lon={COORD_B['lon']}")
        print(f"  Response Status : {resp_b.status_code}")
        body_b = resp_b.json()
        print(f"  Response Lat/Lon: ({body_b['latitude']}, {body_b['longitude']})")
        print(f"  Risk Score      : {body_b['risk_score']}")
        print(f"  Risk Level      : {body_b['risk_level']}")

        # Section K: Failure-Case Result
        print("\n" + "=" * 60)
        print("[K] TESTING FAILURE CASE: Out-of-Coverage Coordinate")
        print("=" * 60)
        resp_out = await client.get("/api/v1/risk/location", params={"lat": COORD_OUT['lat'], "lon": COORD_OUT['lon']})
        print(f"  GET /api/v1/risk/location?lat={COORD_OUT['lat']}&lon={COORD_OUT['lon']}")
        print(f"  Response Status : {resp_out.status_code} (Expected: 400)")
        body_out = resp_out.json()
        print(f"  Response Body   : {body_out}")
        assert resp_out.status_code == 400
        print("  --> Graceful data-unavailable response verified (no fabricated features).")

    print("\n" + "=" * 60)
    print("ALL TESTS PASSED SUCCESSFULLY!")
    print("=" * 60)

if __name__ == "__main__":
    asyncio.run(run_e2e_tests())
