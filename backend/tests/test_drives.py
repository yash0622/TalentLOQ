import pytest
from unittest.mock import AsyncMock, MagicMock
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.jwt_utils import create_access_token

@pytest.mark.asyncio
async def test_placement_drives_full_lifecycle(monkeypatch):
    import app.routers.drives_recruiter as rec_router
    import app.routers.drives_student as st_router

    db_drives = {}
    db_apps = {}

    async def mock_insert_drive(doc):
        did = doc.get("drive_id")
        db_drives[did] = doc
        return MagicMock(inserted_id="drive_id")

    async def mock_find_one_drive(query):
        did = query.get("drive_id")
        return db_drives.get(did)

    async def mock_update_drive(query, update):
        did = query.get("drive_id")
        if did in db_drives:
            if "$set" in update:
                db_drives[did].update(update["$set"])
            if "$inc" in update:
                for k, v in update["$inc"].items():
                    db_drives[did][k] = db_drives[did].get(k, 0) + v
        return MagicMock(modified_count=1)

    class MockDriveCursor:
        def sort(self, *args, **kwargs):
            return self
        def skip(self, *args, **kwargs):
            return self
        def limit(self, *args, **kwargs):
            return self
        async def to_list(self, length=None):
            return list(db_drives.values())

    async def mock_insert_app(doc):
        key = f"{doc.get('drive_id')}_{doc.get('student_id')}"
        db_apps[key] = doc
        return MagicMock(inserted_id="app_id")

    async def mock_find_one_app(query):
        key = f"{query.get('drive_id')}_{query.get('student_id')}"
        return db_apps.get(key)

    async def mock_update_app(query, update):
        key = f"{query.get('drive_id')}_{query.get('student_id')}"
        if key in db_apps:
            db_apps[key].update(update.get("$set", {}))
        return MagicMock(modified_count=1)

    class MockAppCursor:
        def __init__(self, drive_id=None):
            self.drive_id = drive_id
        def sort(self, *args, **kwargs):
            return self
        def skip(self, *args, **kwargs):
            return self
        def limit(self, *args, **kwargs):
            return self
        async def to_list(self, length=None):
            if self.drive_id:
                return [a for a in db_apps.values() if a.get("drive_id") == self.drive_id]
            return list(db_apps.values())

    monkeypatch.setattr(rec_router.drives_collection, "insert_one", mock_insert_drive)
    monkeypatch.setattr(rec_router.drives_collection, "find_one", mock_find_one_drive)
    monkeypatch.setattr(rec_router.drives_collection, "update_one", mock_update_drive)
    monkeypatch.setattr(rec_router.drives_collection, "find", lambda query: MockDriveCursor())
    monkeypatch.setattr(rec_router.applications_collection, "find", lambda query: MockAppCursor(query.get("drive_id")))
    monkeypatch.setattr(rec_router.applications_collection, "find_one", mock_find_one_app)
    monkeypatch.setattr(rec_router.applications_collection, "update_one", mock_update_app)
    monkeypatch.setattr(rec_router.applications_collection, "count_documents", AsyncMock(return_value=1))
    monkeypatch.setattr(rec_router.audit_logs_collection, "insert_one", AsyncMock())
    monkeypatch.setattr(rec_router.students_collection, "count_documents", AsyncMock(return_value=142))
    monkeypatch.setattr("app.routers.recruiter.company_listings_collection.count_documents", AsyncMock(return_value=5))
    monkeypatch.setattr("app.routers.drives_recruiter.notify_on_publish", AsyncMock())

    monkeypatch.setattr(st_router.drives_collection, "find", lambda query: MockDriveCursor())
    monkeypatch.setattr(st_router.drives_collection, "find_one", mock_find_one_drive)
    monkeypatch.setattr(st_router.company_listings_collection, "find", lambda query: MockDriveCursor())
    monkeypatch.setattr(st_router.applications_collection, "find_one", mock_find_one_app)
    monkeypatch.setattr(st_router.applications_collection, "insert_one", mock_insert_app)
    monkeypatch.setattr(st_router.students_collection, "find_one", AsyncMock(return_value={"student_id": "student-101", "has_resume": True, "CGPA": 8.5}))
    monkeypatch.setattr(st_router.audit_logs_collection, "insert_one", AsyncMock())

    recruiter_token = create_access_token(user_id="recruiter-uuid-001", role="recruiter")
    student_token = create_access_token(user_id="student-101", role="student")

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        # 1. Recruiter Creates Drive
        drive_data = {
            "company_name": "UCI Placement Corp",
            "drive_title": "Software Engineering Campus Drive",
            "mode": "on_campus",
            "employment_type": "full_time",
            "location": "SOT Campus",
            "school_tag": "School of Technology",
            "ctc_min": "8.0",
            "ctc_max": "16.0",
            "description": "Full-time hiring for SDE role",
            "qualifications": "B.Tech CSE / BCA",
            "additional_requirements": "Good DSA skills",
            "bond_details": "24 Months",
            "eligibility_criteria_summary": "Min CGPA 7.0",
            "min_cgpa": "7.0",
            "schedule_datetime": "Aug 28, 2026 • 09:00 AM",
            "registration_deadline": "Aug 25, 2026",
            "status_field": "published",
        }
        res = await client.post("/recruiter/drives", data=drive_data, headers={"Authorization": f"Bearer {recruiter_token}"})
        assert res.status_code == 201
        created_drive = res.json()
        drive_id = created_drive["drive_id"]

        # 2. Student Browses Published Drives
        res = await client.get("/drives", headers={"Authorization": f"Bearer {student_token}"})
        assert res.status_code == 200
        drives_data = res.json()
        drives_list = drives_data["items"] if isinstance(drives_data, dict) and "items" in drives_data else drives_data
        assert len(drives_list) == 1
        assert drives_list[0]["company_name"] == "UCI Placement Corp"
        assert drives_list[0]["is_eligible"] is True

        # 3. Student Views Drive Detail
        res = await client.get(f"/drives/{drive_id}", headers={"Authorization": f"Bearer {student_token}"})
        assert res.status_code == 200
        detail = res.json()
        assert detail["drive_id"] == drive_id

        # 4. Student Applies to Drive
        res = await client.post(f"/drives/{drive_id}/apply", headers={"Authorization": f"Bearer {student_token}"})
        assert res.status_code == 201

        # 5. Student Checks Status
        res = await client.get(f"/drives/{drive_id}/my-status", headers={"Authorization": f"Bearer {student_token}"})
        assert res.status_code == 200
        status_info = res.json()
        assert status_info["applied"] is True

        # 6. Recruiter Lists Applicants
        res = await client.get(f"/recruiter/drives/{drive_id}/applicants", headers={"Authorization": f"Bearer {recruiter_token}"})
        assert res.status_code == 200
        applicants_data = res.json()
        applicants = applicants_data["items"] if isinstance(applicants_data, dict) and "items" in applicants_data else applicants_data
        assert len(applicants) == 1
        assert applicants[0]["student_id"] == "student-101"

        # 7. Recruiter Advances Round 1 (Pass)
        res = await client.patch(
            f"/recruiter/drives/{drive_id}/applicants/student-101/round",
            json={"result": "pass"},
            headers={"Authorization": f"Bearer {recruiter_token}"}
        )
        assert res.status_code == 200
        assert res.json()["result"] == "pass"

        # 8. Recruiter Checks Stats
        res = await client.get("/recruiter/stats", headers={"Authorization": f"Bearer {recruiter_token}"})
        assert res.status_code == 200
        stats = res.json()
        assert "total_registered_students" in stats
        assert "total_active_drives" in stats
        assert "total_offers_made" in stats
