import pytest
from unittest.mock import MagicMock
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.jwt_utils import create_access_token

@pytest.mark.asyncio
async def test_email_draft_generation_and_tracking(monkeypatch):
    import app.routers.drives_student as st_router
    import app.routers.drives_recruiter as rec_router

    db_drives = {
        "drive_123": {
            "drive_id": "drive_123",
            "company_name": "Acme Innovations",
            "company_email": "careers@acme.com",
            "interview_job": "Software Engineer",
            "status": "published",
        }
    }
    db_students = {
        "student_777": {
            "student_id": "student_777",
            "full_name": "Rahul Verma",
            "email": "rahul.v@gsfc.edu.in",
            "phone_number": "+91 98765 43210",
            "course": "B.Tech Computer Science",
            "CGPA": 8.75,
            "has_resume": True,
        }
    }
    db_apps = {
        "drive_123_student_777": {
            "drive_id": "drive_123",
            "student_id": "student_777",
            "status": "applied",
        }
    }

    async def mock_find_one_drive(query):
        did = query.get("drive_id") or query.get("listing_id")
        return db_drives.get(did)

    async def mock_find_one_student(query):
        sid = query.get("student_id") or query.get("user_id")
        return db_students.get(sid)

    async def mock_find_one_app(query):
        key = f"{query.get('drive_id')}_{query.get('student_id')}"
        return db_apps.get(key)

    async def mock_update_many_apps(query, update):
        sid = query.get("student_id")
        for key, doc in db_apps.items():
            if doc.get("student_id") == sid:
                doc.update(update.get("$set", {}))
        return MagicMock(modified_count=1)

    monkeypatch.setattr(st_router.drives_collection, "find_one", mock_find_one_drive)
    monkeypatch.setattr(st_router.company_listings_collection, "find_one", mock_find_one_drive)
    monkeypatch.setattr(st_router.students_collection, "find_one", mock_find_one_student)
    monkeypatch.setattr(st_router.applications_collection, "find_one", mock_find_one_app)
    monkeypatch.setattr(st_router.applications_collection, "update_many", mock_update_many_apps)

    student_token = create_access_token(user_id="student_777", role="student")
    recruiter_token = create_access_token(user_id="recruiter_1", role="recruiter")

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        # 1. GET /drives/drive_123/email-draft
        resp = await client.get(
            "/drives/drive_123/email-draft",
            headers={"Authorization": f"Bearer {student_token}"},
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["to"] == "careers@acme.com"
        assert data["subject"] == "Application for Software Engineer — Rahul Verma"
        assert "Dear Hiring Team at Acme Innovations," in data["body"]
        assert "Rahul Verma" in data["body"]
        assert "rahul.v@gsfc.edu.in" in data["body"]
        assert "+91 98765 43210" in data["body"]
        assert "CGPA of 8.75" in data["body"]

        # 2. POST /drives/drive_123/email-draft/mark-sent
        resp_mark = await client.post(
            "/drives/drive_123/email-draft/mark-sent",
            headers={"Authorization": f"Bearer {student_token}"},
        )
        assert resp_mark.status_code == 200
        assert "email_client_opened_at" in resp_mark.json()
        assert "email_client_opened_at" in db_apps["drive_123_student_777"]

        # 3. Security check — reject recruiter access to student email draft route
        resp_sec = await client.get(
            "/drives/drive_123/email-draft",
            headers={"Authorization": f"Bearer {recruiter_token}"},
        )
        assert resp_sec.status_code == 403

@pytest.mark.asyncio
async def test_email_draft_missing_phone_omission(monkeypatch):
    import app.routers.drives_student as st_router

    db_drives = {
        "drive_999": {
            "drive_id": "drive_999",
            "company_name": "Tech Corp",
            "company_email": "hr@techcorp.com",
            "interview_job": "Backend Developer",
        }
    }
    db_students = {
        "student_888": {
            "student_id": "student_888",
            "full_name": "Priya Sharma",
            "email": "priya@gsfc.edu.in",
            "phone_number": "",  # Empty phone
            "course": "BCA",
            "CGPA": 9.1,
        }
    }

    async def mock_find_one_drive(query):
        return db_drives.get(query.get("drive_id"))

    async def mock_find_one_student(query):
        return db_students.get(query.get("student_id"))

    monkeypatch.setattr(st_router.drives_collection, "find_one", mock_find_one_drive)
    monkeypatch.setattr(st_router.company_listings_collection, "find_one", mock_find_one_drive)
    monkeypatch.setattr(st_router.students_collection, "find_one", mock_find_one_student)

    student_token = create_access_token(user_id="student_888", role="student")

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        resp = await client.get(
            "/drives/drive_999/email-draft",
            headers={"Authorization": f"Bearer {student_token}"},
        )
        assert resp.status_code == 200
        body = resp.json()["body"]
        lines = body.split("\n")
        # Ensure name and email are present, but no trailing blank/placeholder line for phone
        assert lines[-1] == "priya@gsfc.edu.in"
