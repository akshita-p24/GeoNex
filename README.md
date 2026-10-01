# GeoNex — National Landslide Early Warning & Risk-to-Action Platform

> **Smart India Hackathon (SIH 2026) | Problem Statement ID: 26001**  
> **Region Focus:** North Eastern Region (NER) — Arunachal Pradesh & Assam Himalayas  
> **Target:** AI-Powered Real-Time Landslide Risk Monitoring, Field Verification & Emergency Response Dispatch

---

## 🏗️ System Architecture

The GeoNex platform follows a clean, decoupled three-tier architecture:

```
┌────────────────────────────────────────────────────────┐
│                   Flutter Mobile App                   │
│        (Android / Field Officer & Citizen UI)          │
└──────────────────────────┬─────────────────────────────┘
                           │  HTTP / REST + WebSocket
                           │  Authorization: Bearer <JWT>
                           ▼
┌────────────────────────────────────────────────────────┐
│                 FastAPI Backend Engine                 │
│         (Authentication, RBAC, ML Inference,           │
│           Geo-Tagging, Early Warning Dispatch)         │
└──────────────────────────┬─────────────────────────────┘
                           │  SQLAlchemy (Asyncpg)
                           │  Native SQL & Geometry
                           ▼
┌────────────────────────────────────────────────────────┐
│             Supabase Cloud Infrastructure              │
│       • PostgreSQL 17.6 (Relational Database)          │
│       • PostGIS 3.3 (Spatial & Geospatial Engine)      │
└────────────────────────────────────────────────────────┘
```

> **Important Architecture Notes:**
> - **FastAPI** handles all business logic, user authentication, role authorization, and ML orchestration.
> - **Supabase** acts strictly as the managed cloud **PostgreSQL + PostGIS** database provider.
> - Flutter communicates exclusively with FastAPI via standard JWT Bearer tokens. Direct client-side database connections are prohibited.

---

## 🌟 Key Capabilities & Features

### 1. 🔐 Real User Authentication & Role-Based Access Control (RBAC)
- **Sign Up:** Self-registration for **Citizen Reporters** and **Field Officers**. Administrative account registration is blocked on the public API (HTTP 403 Forbidden).
- **Password Security:** Passwords hashed with industry-standard **bcrypt**; plaintext passwords are never stored.
- **JWT Authorization:** Standard OAuth2 Bearer token generation with expiry; profile inspection via `GET /api/v1/auth/me`.
- **Role Hierarchy:**
  - `CITIZEN`: Submits geo-tagged incident reports, tracks report status, receives emergency evacuation alerts.
  - `FIELD_OFFICER`: Performs ground inspections, verifies/rejects citizen reports (`POST /verify`), attaches inspection remarks.
  - `ADMIN` / `DISTRICT_ADMIN`: Full situational awareness, GIS layer configuration, and disaster authority actions.

### 2. 🗺️ Citizen → Field Officer → Authority Workflow
- **Report Submission:** Citizens capture hazard type (`LANDSLIDE`, `ROCKFALL`, `CRACK`, `DEBRIS_FLOW`), description, GPS latitude/longitude, and timestamp.
- **Spatial Geometry:** Stored as native PostGIS `Point(lng, lat, 4326)` in PostgreSQL.
- **Inspection & Verification:** Field Officers review pending reports and record ground truth decisions (`VERIFY`, `REJECT`, `NEEDS_INFORMATION`) with audit logging.
- **Authority Review:** High-severity verified reports trigger early warning broadcasts and priority evacuation dispatches.

### 3. 🔄 Offline-First Reporting & Idempotency
- When network coverage is unavailable in remote mountain areas, reports are queued locally in persistent storage.
- Each report is tagged with a unique `client_report_id` UUID generated on the device.
- Re-transmissions upon network recovery are strictly idempotent: duplicates are detected by the backend and return the existing record without duplicate DB entries.

### 4. 📸 Evidence Media Upload
- Supports direct multipart/form-data upload to `POST /api/v1/reports/{report_id}/media`.
- Computes SHA-256 digest on reception, verifies ownership, and stores file metadata in the `media` table.

---

## 🗄️ Database Tables (Supabase PostgreSQL + PostGIS)

All tables are defined in SQLAlchemy models and managed via Alembic:

| Table Name | Description | Key Fields |
|---|---|---|
| `users` | User accounts & credentials | `id`, `email`, `hashed_password`, `role`, `is_active` |
| `field_reports` | Geo-tagged hazard reports | `id`, `user_id`, `client_report_id`, `location` (Point), `status` |
| `field_verifications` | Officer verification decisions | `id`, `report_id`, `officer_id`, `decision`, `remarks` |
| `media` | Attached photos & video evidence | `id`, `report_id`, `media_url`, `file_hash`, `file_size` |
| `audit_logs` | Immutable security audit trail | `id`, `user_id`, `action`, `entity_type`, `entity_id` |
| `alerts` | Dispatched warning alerts | `id`, `severity`, `title`, `affected_radius_km` |
| `villages` | Settlement GIS points & census | `id`, `name`, `district`, `location` |
| `roads` | Highway network lines | `id`, `road_name`, `geom` (LineString) |

---

## 🚀 Getting Started

### Prerequisites
- Python 3.12+ (in `backend/.venv`)
- Flutter SDK 3.29+
- Active Supabase project with PostGIS extension enabled

### 1. Backend Setup

```bash
cd backend

# Activate virtual environment
.\.venv\Scripts\activate

# Configure environment variables in backend/.env:
# DATABASE_URL=postgresql+asyncpg://postgres.<ref>:<pass>@aws-0-<region>.pooler.supabase.com:5432/postgres
# SECRET_KEY=your-jwt-secret-key-32-chars

# Verify database and PostGIS connectivity
python check_db.py

# Seed initial demonstration accounts
python seed_demo_users.py

# Run comprehensive end-to-end integration test suite
python test_full_suite.py

# Launch FastAPI development server
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

- **Interactive API Documentation:** http://127.0.0.1:8000/docs
- **Health Check Endpoint:** http://127.0.0.1:8000/health

### 2. Frontend Setup (Flutter)

```bash
cd frontend

# Install dependencies
flutter pub get

# Verify code integrity
flutter analyze

# Run on connected physical Android device (via LAN)
flutter run -d <device-id>
```

#### Android Connectivity Configuration:
- **Android Emulator:** Set backend base URL to `http://10.0.2.2:8000`
- **Physical Android Phone (via USB/Wi-Fi):** Set backend base URL to your PC's LAN IP, e.g. `http://10.235.29.64:8000`
- Configure in `frontend/lib/core/services/auth_service.dart` (`kBackendBaseUrl`) or dynamically via Settings in the app.

---

## 👥 Seeded Demonstration Accounts

For verification and testing, the database includes:

| Role | Email | Password | Permissions |
|---|---|---|---|
| **SDMA Administrator** | `admin@geonex.in` | `admin1234` | Full system access, all reports & GIS |
| **Field Officer** | `officer@geonex.in` | `officer1234` | View pending reports, verify/reject hazards |
| **Citizen Reporter** | `citizen@geonex.in` | `citizen1234` | Submit incident reports, view own reports |

---

## 🧪 Automated Test Suite

Run all verification tests against the live Supabase PostgreSQL database:

```bash
python backend/test_full_suite.py
```

**Test Coverage:**
1. Health Check (`GET /health` -> 200 OK)
2. User Registration (`POST /api/v1/auth/register` -> 201 Created)
3. OAuth2 Form Login (`POST /api/v1/auth/login` -> 200 OK + JWT)
4. JSON Body Login (`POST /api/v1/auth/login` -> 200 OK + JWT)
5. User Profile Inspection (`GET /api/v1/auth/me` with Bearer token)
6. Citizen Report Creation with PostGIS EWKB Point geometry
7. Idempotent Duplicate Re-submission (same `client_report_id`)
8. Multipart Media Upload with SHA-256 Digest calculation
9. Field Officer Report Verification & Audit Log generation
10. Server-Side RBAC Enforcement: Citizen denied verification (HTTP 403)
11. Security Protection: Public self-registration as ADMIN blocked (HTTP 403)