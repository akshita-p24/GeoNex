import asyncio
import uuid
from datetime import datetime, timezone
import httpx
from app.main import app

async def run_full_suite():
    print("=" * 65)
    print("GEONEX FULL BACKEND, SUPABASE POSTGRESQL & WORKFLOW AUDIT TEST")
    print("=" * 65)

    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        # 1. Health check
        print("\n[1] TESTING HEALTH CHECK:")
        resp = await client.get("/health")
        print(f"  GET /health -> {resp.status_code}, {resp.json()}")
        assert resp.status_code == 200, "Health check failed"

        # 2. Registration
        test_email = f"citizen_{uuid.uuid4().hex[:6]}@geonex.in"
        print(f"\n[2] TESTING USER REGISTRATION (email: {test_email}):")
        reg_payload = {
            "email": test_email,
            "full_name": "Test Citizen User",
            "password": "Password123!",
            "role": "CITIZEN"
        }
        resp = await client.post("/api/v1/auth/register", json=reg_payload)
        print(f"  POST /api/v1/auth/register -> {resp.status_code}")
        assert resp.status_code == 201, f"Registration failed: {resp.text}"
        user_data = resp.json()
        print(f"  Created user: {user_data['email']}, role: {user_data['role']}, id: {user_data['id']}")

        # 3. Login (Form-data)
        print("\n[3] TESTING LOGIN (OAuth2 Form-encoded):")
        resp = await client.post(
            "/api/v1/auth/login",
            data={"username": test_email, "password": "Password123!"},
            headers={"Content-Type": "application/x-www-form-urlencoded"}
        )
        print(f"  POST /api/v1/auth/login (form) -> {resp.status_code}")
        assert resp.status_code == 200, f"Login form failed: {resp.text}"
        login_res = resp.json()
        token = login_res["access_token"]
        print(f"  JWT Token received (type: {login_res['token_type']}, length: {len(token)})")

        # 4. Login (JSON body)
        print("\n[4] TESTING LOGIN (JSON body):")
        resp = await client.post(
            "/api/v1/auth/login",
            json={"email": test_email, "password": "Password123!"}
        )
        print(f"  POST /api/v1/auth/login (json) -> {resp.status_code}")
        assert resp.status_code == 200, f"Login JSON failed: {resp.text}"

        # 5. GET /auth/me
        print("\n[5] TESTING /auth/me WITH JWT:")
        resp = await client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"}
        )
        print(f"  GET /api/v1/auth/me -> {resp.status_code}, User: {resp.json()['email']}")
        assert resp.status_code == 200, "Get me failed"

        # 6. Citizen Report Creation + PostGIS Point
        client_rep_id = str(uuid.uuid4())
        print(f"\n[6] TESTING CITIZEN REPORT CREATION (idempotency key: {client_rep_id}):")
        report_payload = {
            "client_report_id": client_rep_id,
            "report_type": "ROCKFALL",
            "description": "Noticeable soil slippage and rocks falling onto highway corridor after heavy rain.",
            "latitude": 27.15,
            "longitude": 93.70,
            "capture_timestamp": datetime.now(timezone.utc).isoformat()
        }
        resp = await client.post(
            "/api/v1/reports",
            json=report_payload,
            headers={"Authorization": f"Bearer {token}"}
        )
        print(f"  POST /api/v1/reports -> {resp.status_code}")
        assert resp.status_code == 201, f"Report creation failed: {resp.text}"
        report_data = resp.json()
        report_id = report_data["id"]
        print(f"  Created Report ID: {report_id}, Status: {report_data['status']}")

        # 7. Idempotency Check: Resubmit same client_report_id
        print("\n[7] TESTING IDEMPOTENT RE-SUBMISSION (Same client_report_id):")
        resp_dup = await client.post(
            "/api/v1/reports",
            json=report_payload,
            headers={"Authorization": f"Bearer {token}"}
        )
        print(f"  POST /api/v1/reports (duplicate key) -> {resp_dup.status_code}")
        assert resp_dup.status_code in (200, 201), "Duplicate submission did not succeed"
        assert resp_dup.json()["id"] == report_id, "Duplicate submission did not return identical report ID!"
        print("  --> Idempotency verified: exactly same report returned, no duplicate created.")

        # 8. Media Upload for Report
        print("\n[8] TESTING REPORT MEDIA UPLOAD:")
        sample_image_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00\xff\xdb\x00C\x00" + (b"\x00" * 100)
        files = {"file": ("landslide_evidence.jpg", sample_image_bytes, "image/jpeg")}
        resp_media = await client.post(
            f"/api/v1/reports/{report_id}/media",
            files=files,
            headers={"Authorization": f"Bearer {token}"}
        )
        print(f"  POST /api/v1/reports/{report_id}/media -> {resp_media.status_code}")
        assert resp_media.status_code == 201, f"Media upload failed: {resp_media.text}"
        media_info = resp_media.json()
        print(f"  Media saved: {media_info['media_url']}, hash: {media_info['file_hash'][:16]}...")

        # 9. Field Officer Verification & Audit Log
        print("\n[9] TESTING FIELD OFFICER LOGIN & VERIFICATION:")
        # Login as seeded officer
        resp_fo = await client.post(
            "/api/v1/auth/login",
            data={"username": "officer@geonex.in", "password": "officer1234"},
            headers={"Content-Type": "application/x-www-form-urlencoded"}
        )
        assert resp_fo.status_code == 200, f"Officer login failed: {resp_fo.text}"
        fo_token = resp_fo.json()["access_token"]
        print(f"  Field Officer authenticated: officer@geonex.in")

        # Verify the citizen report
        verify_payload = {
            "decision": "VERIFY",
            "remarks": "On-ground site inspected. Active tension cracks observed on slope face. Verified."
        }
        resp_verify = await client.post(
            f"/api/v1/reports/{report_id}/verify",
            json=verify_payload,
            headers={"Authorization": f"Bearer {fo_token}"}
        )
        print(f"  POST /api/v1/reports/{report_id}/verify -> {resp_verify.status_code}")
        assert resp_verify.status_code == 200, f"Verification failed: {resp_verify.text}"
        print(f"  Verification result: {resp_verify.json()['decision']}, Report status updated to VERIFIED")

        # 10. Role Protection: Citizen attempting officer verification must get 403 Forbidden
        print("\n[10] TESTING RBAC 403 FORBIDDEN (Citizen attempting verification):")
        resp_forbid = await client.post(
            f"/api/v1/reports/{report_id}/verify",
            json=verify_payload,
            headers={"Authorization": f"Bearer {token}"} # using citizen token
        )
        print(f"  Citizen -> /verify -> Status: {resp_forbid.status_code}")
        assert resp_forbid.status_code == 403, f"Expected 403 Forbidden, got {resp_forbid.status_code}"
        print("  --> Server-side RBAC enforced: HTTP 403 Forbidden returned.")

        # 11. Security Check: Ordinary user cannot register as ADMIN
        print("\n[11] TESTING SECURITY RESTRICTION (Public self-registration as ADMIN):")
        admin_reg_payload = {
            "email": f"fake_admin_{uuid.uuid4().hex[:6]}@geonex.in",
            "full_name": "Rogue Admin Attempt",
            "password": "Password123!",
            "role": "ADMIN"
        }
        resp_admin_reg = await client.post("/api/v1/auth/register", json=admin_reg_payload)
        print(f"  POST /api/v1/auth/register (role: ADMIN) -> Status: {resp_admin_reg.status_code}")
        assert resp_admin_reg.status_code == 403, f"Expected 403 Forbidden for ADMIN registration, got {resp_admin_reg.status_code}"
        print("  --> Security restriction verified: Self-registration as ADMIN is strictly prohibited.")

    print("\n" + "=" * 65)
    print("ALL WORKFLOW & POSTGIS DATABASE TESTS PASSED WITH 100% SUCCESS!")
    print("=" * 65)

if __name__ == "__main__":
    asyncio.run(run_full_suite())
