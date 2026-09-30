# GeoNex — Landslide Risk Monitoring & Early Warning System

> **Smart India Hackathon (SIH) 2026** | Branch: `integrate-member3`

A production-grade landslide early-warning platform combining a Flutter mobile/desktop app, a FastAPI AI backend, real GIS data, and live environmental feeds to deliver end-to-end risk predictions and actionable alerts.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [GIS Study Areas](#gis-study-areas)
- [ML Pipeline](#ml-pipeline)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Backend Setup](#backend-setup)
- [Running on Android](#running-on-android)
- [Project Structure](#project-structure)
- [Recent Changes](#recent-changes)
- [API Reference](#api-reference)

---

## Overview

GeoNex is a full-stack decision-intelligence application for real-time landslide risk assessment and early warning. It ingests live weather data, extracts GIS terrain features (slope, aspect, soil, DEM, NDVI, proximity to rivers/roads), runs a trained Random Forest ensemble, and delivers risk scores to field officers and administrators — all in real time.

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│               Flutter Frontend (Mobile / Desktop)     │
│  Dashboard · Risk Map · Alerts · Citizen Reporting   │
│  Field Verification · Settings · Notifications       │
└────────────────────┬─────────────────────────────────┘
                     │ HTTPS / REST
┌────────────────────▼─────────────────────────────────┐
│               FastAPI Backend (Python)                │
│  /risk/location · /reports · /alerts · /auth         │
│  RiskEngine interface → FutureRiskApiEngine          │
└────┬──────────────┬────────────────┬─────────────────┘
     │              │                │
┌────▼────┐  ┌──────▼──────┐  ┌─────▼──────────────┐
│  GIS    │  │ Open-Meteo  │  │  Random Forest ML  │
│ Rasters │  │ Live Weather│  │  (Static+Dynamic)  │
│ Vectors │  │    API      │  │  joblib pipelines  │
└─────────┘  └─────────────┘  └────────────────────┘
```

---

## Features

### 🗺️ Interactive Risk Map
- Real coordinate-based markers for **Infrastructure**, **Citizen Reports**, and **Historical Landslides**
- Layer control sheet: toggle each layer independently from within the map
- Map rotation enabled for natural device-tilt navigation (rotation lock removed)
- Markers sourced from backend data, not hardcoded placeholders

### 🤖 AI Risk Engine (End-to-End)
- **Static GIS feature extraction** — slope, aspect, elevation, curvature, soil type, distance to roads/rivers from real raster and vector datasets
- **Live environmental data** — rainfall, temperature, humidity, wind speed from Open-Meteo (no API key required)
- **Random Forest inference** — two separate pipelines (static + dynamic) trained on historical landslide inventory
- **Dynamic coordinate support** — predictions scoped to actual lat/lon; hardcoded coordinates removed
- **Graceful out-of-area handling** — returns HTTP 400 if coordinates fall outside supported GIS study areas

### 🚨 Alerts & Notifications
- In-app notifications for risk threshold breaches
- Citizen report **rejected** notifications added alongside existing verified-report alerts
- Alert Engine triggers automatically when risk score exceeds configurable threshold

### 👥 Citizen → Field Officer → Administrator Workflow
- Citizens submit geotagged landslide reports (photos + description)
- Field officers receive assignments and perform on-site verification
- Administrators review, approve/reject, and trigger official alerts
- All state persisted via PostgreSQL through the FastAPI backend

### 🌐 Localisation
- Multi-language support via `AppLocalizations`
- Language selector in Settings; locale persisted via `AppState.selectedLocale`
- `MaterialApp` locale driven by state — English default, additional locales ready

### ⚙️ Settings & Layer Control
- Settings: language selection, map layer toggles, notification preferences
- Layer control rendered as a bottom sheet for quick in-map access

---

## GIS Study Areas

GeoNex contains pre-processed GIS datasets for **two study areas** in Arunachal Pradesh:

### 1. Papum Pare
| Layer | Format |
|---|---|
| Administrative boundary | Shapefile / GeoJSON |
| Roads | Shapefile |
| Rivers | Shapefile |
| Villages | Shapefile |
| DEM (Digital Elevation Model) | GeoTIFF raster |
| Slope | GeoTIFF raster |
| Aspect | GeoTIFF raster |
| Curvature | GeoTIFF raster |
| Soil type | GeoTIFF raster |

### 2. West Kameng
| Layer | Format |
|---|---|
| Roads | Shapefile |
| Rivers | Shapefile |
| Villages | Shapefile |
| DEM | GeoTIFF raster |
| Slope | GeoTIFF raster |
| Aspect | GeoTIFF raster |
| Curvature | GeoTIFF raster |
| Soil type | GeoTIFF raster |
| NDVI | GeoTIFF raster |

```text
gis/
├── papum_pare/
└── west_kameng/
```

---

## ML Pipeline

### Static Features (10)
Extracted from GIS rasters at prediction coordinates:

| # | Feature | Source |
|---|---|---|
| 1 | `slope` | Slope raster |
| 2 | `aspect` | Aspect raster |
| 3 | `elevation` | DEM raster |
| 4 | `curvature` | Curvature raster |
| 5 | `soil_type` | Soil raster |
| 6 | `ndvi` | NDVI raster (West Kameng) |
| 7 | `dist_to_road` | Road vector proximity |
| 8 | `dist_to_river` | River vector proximity |
| 9 | `land_use` | Derived from soil/NDVI |
| 10 | `geology` | Derived from soil |

### Dynamic Features (Open-Meteo)
| Feature | Description |
|---|---|
| `rainfall_mm` | Current precipitation (mm) |
| `temperature_c` | Air temperature (°C) |
| `humidity_pct` | Relative humidity (%) |
| `wind_speed_kmh` | Wind speed at 10 m |

### Inference Flow
```
POST /risk/location?lat=X&lon=Y
       │
       ├─► GIS Feature Extraction (rasterio + geopandas)
       │         └─► Static feature vector [10 dims]
       │
       ├─► Open-Meteo API fetch
       │         └─► Dynamic feature vector [4 dims]
       │
       ├─► Static RF Pipeline  → static_score
       ├─► Dynamic RF Pipeline → dynamic_score
       │
       ├─► Ensemble blend → final_risk_score [0.0–1.0]
       │
       ├─► Persist to DB (risk_predictions table)
       └─► Alert Engine threshold check → trigger alert if needed
```

### Model Files
```
backend/ml/models/
├── static_pipeline.joblib
└── dynamic_pipeline.joblib
```

---

## Prerequisites

| Tool | Version |
|---|---|
| Flutter SDK | ≥ 3.6.0 |
| Dart SDK | bundled with Flutter |
| Python | ≥ 3.10 |
| PostgreSQL | ≥ 14 |
| Git | any recent |
| Android SDK | for Android target |

---

## Quick Start

```bash
# 1. Clone the repository
git clone <your-repo-url>
git checkout integrate-member3

# 2. Install Flutter dependencies
cd frontend
flutter pub get

# 3. Run on Chrome (fastest)
flutter run -d chrome

# 4. Run on connected Android device
flutter run -d <device-id>

# 5. Run on Windows desktop
flutter run -d windows
```

---

## Backend Setup

```bash
cd backend

# Create and activate virtual environment
python -m venv .venv
.venv\Scripts\activate          # Windows
# source .venv/bin/activate     # Linux / macOS

# Install Python dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env: set DATABASE_URL, SECRET_KEY, etc.

# Run database migrations
alembic upgrade head

# Start the FastAPI server
uvicorn api:app --reload --host 0.0.0.0 --port 8000
```

### Verify the ML pipeline end-to-end
```bash
python test_pipeline_e2e.py
# Expected: INFERENCE TEST: PASS for both study areas
```

---

## Running on Android

1. Enable **Developer Options** and **USB Debugging** on the device.
2. Connect via USB and confirm the "Allow USB Debugging" prompt.
3. Verify detection:
   ```bash
   flutter devices
   ```
4. Deploy:
   ```bash
   cd frontend
   flutter run -d <device-id>
   ```

---

## Project Structure

```
GeoNex/
├── frontend/                  # Flutter application
│   └── lib/
│       ├── main.dart
│       ├── app/               # Router, themes, global config
│       ├── ai/                # Risk engine interface & implementations
│       │   ├── risk_engine.dart             # Abstract interface
│       │   ├── future_risk_api_engine.dart  # Live API (production)
│       │   └── mock_risk_engine.dart        # Offline mock
│       ├── core/              # Constants, theme tokens, utilities
│       ├── features/
│       │   ├── dashboard/
│       │   ├── risk_map/
│       │   ├── alerts/
│       │   ├── citizen_reporting/
│       │   ├── field_verification/
│       │   └── settings/
│       ├── state/             # AppState (locale, user, etc.)
│       └── widgets/           # Shared widgets (map canvas, etc.)
│
├── backend/                   # FastAPI AI backend
│   ├── api.py                 # App entry point
│   ├── inference.py           # RF model loading & prediction
│   ├── test_pipeline_e2e.py   # End-to-end pipeline validation script
│   ├── test_ml.py             # ML unit tests
│   ├── requirements.txt
│   ├── app/
│   │   ├── routers/           # FastAPI route handlers
│   │   ├── services/
│   │   │   ├── gis_features.py       # GIS raster/vector extraction
│   │   │   └── live_data/
│   │   │       └── open_meteo.py     # Live weather fetcher
│   │   └── models/            # SQLAlchemy ORM models
│   └── ml/models/             # Trained joblib pipelines
│
├── gis/                       # Raw GIS datasets
│   ├── papum_pare/
│   └── west_kameng/
│
└── dashboard/                 # Admin web dashboard (separate)
```

---

## Recent Changes

### Step 1 — UI / Workflow Remediation

| Area | Change |
|---|---|
| **Map Layers** | Added real coordinate-based markers (Infrastructure, Citizen Reports, Historical Landslides); Settings → Map Layers converted to an interactive bottom sheet with per-layer toggles |
| **Map Rotation** | Removed `InteractiveFlag.all` rotation lock; map now rotates with device/gesture |
| **Localisation** | Added `AppState.selectedLocale`, `setLocale()`, localisation ARB files; Settings connected to locale switching; `MaterialApp` locale state-driven |
| **Notifications** | Retained verified-report alert flow; added **rejected-report** notification; alert engine triggers on risk threshold breach |
| **Dashboard** | Text density confirmed appropriate; no unnecessary changes |
| **Field Verification** | Verified Citizen → Field Officer → Admin pipeline end-to-end; fixed `unreachable_switch_default` lint warnings |
| **HTTP Backend** | Removed unnecessary cast in `http_backend_client.dart` |

### Step 2 — Static GIS Feature Extraction

- `backend/app/services/gis_features.py` extracts slope, aspect, elevation, curvature, soil type, NDVI, and distance-to-road/river from real GeoTIFF and Shapefile data using **rasterio** and **geopandas**
- Coordinate lookup returns the exact pixel value at `(lat, lon)` from the matching study-area raster
- Out-of-bounds coordinates return HTTP 400 with a clear error message

### Step 3 — Live Environmental Data

- `backend/app/services/live_data/open_meteo.py` fetches live rainfall, temperature, humidity, and wind speed from the **Open-Meteo** free weather API (no API key required)
- Data fetched per-prediction using the same `(lat, lon)` as the risk endpoint

### Step 4 — Real ML Inference Integration

- `backend/inference.py` loads two **Random Forest** pipelines (`static_pipeline.joblib`, `dynamic_pipeline.joblib`) trained on historical landslide inventory data
- `frontend/lib/ai/risk_engine.dart` interface updated with explicit `latitude`/`longitude` parameters
- `frontend/lib/ai/future_risk_api_engine.dart` — **hardcoded coordinates removed**; all predictions now use the actual location coordinates
- `frontend/lib/ai/mock_risk_engine.dart` — updated to match new interface signature
- `backend/test_pipeline_e2e.py` — created for full-stack validation (GIS → Weather → ML → DB → Alert)

---

## API Reference

### `POST /risk/location`
Compute landslide risk for a coordinate.

**Query params**: `lat` (float), `lon` (float)

**Response**:
```json
{
  "risk_score": 0.73,
  "risk_level": "HIGH",
  "static_score": 0.68,
  "dynamic_score": 0.79,
  "features": { "slope": 28.4, "rainfall_mm": 12.3, "..." : "..." },
  "study_area": "papum_pare"
}
```

### `GET /reports`
List all citizen-submitted landslide reports.

### `POST /reports`
Submit a citizen landslide report (multipart form with optional photo).

### `PATCH /reports/{id}/verify`
Field officer submits on-site verification result.

### `PATCH /reports/{id}/approve`
Administrator approves/rejects a verified report and triggers alerts.

### `GET /alerts`
List active alerts sorted by severity.

---

## Contributing

Branch convention: `integrate-member<N>`

```bash
git checkout -b integrate-member3
git add .
git commit -m "feat: descriptive message"
git push origin integrate-member3
```

---

## License

Smart India Hackathon 2026 — Internal project. All rights reserved.