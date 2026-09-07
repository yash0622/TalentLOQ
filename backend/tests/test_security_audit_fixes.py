import pytest
from unittest.mock import AsyncMock, MagicMock, patch
import httpx
from httpx import AsyncClient
from app.main import app
from app.config import settings, Settings
from app.jwt_utils import create_access_token
from app.middleware import check_ip_in_cidrs

import os

def test_show_dev_otp_default_is_false():
    """Vulnerability #2 Fix: Ensure SHOW_DEV_OTP is False by default."""
    assert settings.SHOW_DEV_OTP is False
    with patch.dict(os.environ, {}, clear=True):
        fallback = os.environ.get("SHOW_DEV_OTP", "false").lower() == "true"
        assert fallback is False

def test_check_ip_in_cidrs_list_and_str():
    """Vulnerability #10 Fix: Ensure check_ip_in_cidrs handles list and str without error."""
    assert check_ip_in_cidrs("127.0.0.1", ["127.0.0.1", "192.168.1.0/24"]) is True
    assert check_ip_in_cidrs("10.0.0.5", ["127.0.0.1", "192.168.1.0/24"]) is False
    assert check_ip_in_cidrs("127.0.0.1", "127.0.0.1, 192.168.1.0/24") is True
    assert check_ip_in_cidrs("10.0.0.5", "127.0.0.1, 192.168.1.0/24") is False

@pytest.mark.asyncio
async def test_backdoor_password_rejected(monkeypatch):
    """Vulnerability #1 Fix: Verify hardcoded passwords are completely rejected."""
    from app.routers import auth as auth_router
    from app.security import hash_password

    mock_recruiter = {
        "user_id": "recruiter_real_id",
        "email": "talentloq.recruiter@gmail.com",
        "password_hash": hash_password("RealLegitPassword2026!"),
        "role": "recruiter",
        "trusted_devices": [],
        "failed_login_attempts": 0,
        "lockout_until": None,
        "is_verified": True,
        "must_change_password": False,
    }
    monkeypatch.setattr(auth_router.users_collection, "find_one", AsyncMock(return_value=mock_recruiter))
    monkeypatch.setattr(auth_router.users_collection, "update_one", AsyncMock())
    monkeypatch.setattr(auth_router.audit_logs_collection, "insert_one", AsyncMock())

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        # Attempt login with backdoor string
        res = await ac.post("/auth/login", json={
            "email": "talentloq.recruiter@gmail.com",
            "password": "ChangeMeRecruiter2026!"
        })
        assert res.status_code == 401
        assert "Incorrect password" in res.text

        # Attempt with second backdoor string
        res2 = await ac.post("/auth/login", json={
            "email": "talentloq.recruiter@gmail.com",
            "password": "telentloq@authentication"
        })
        assert res2.status_code == 401
        assert "Incorrect password" in res2.text

@pytest.mark.asyncio
async def test_student_registration_domain_restriction(monkeypatch):
    """Vulnerability #9 Fix: Reject domains containing gsfcuniversity in user part but not actual domain."""
    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        # Attacker tries to bypass with substring
        res = await ac.post("/auth/register", json={
            "email": "attacker-gsfcuniversity@gmail.com",
            "password": "Password123!",
            "full_name": "Attacker",
            "education": "B.Tech",
            "CGPA": 9.0,
            "skills": ["Python"]
        })
        assert res.status_code == 400
        assert "restricted to GSFC University students" in res.text

@pytest.mark.asyncio
async def test_student_cannot_admin_override():
    """Vulnerability #4 Fix: A student token calling /admin-override must get 403 Forbidden."""
    student_token = create_access_token(user_id="student_123", role="student")
    headers = {"Authorization": f"Bearer {student_token}"}

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.patch(
            "/documents/profile/verified-data/CGPA/admin-override",
            json={"new_value": 10.0, "notes": "Hacked self"},
            headers=headers
        )
        assert res.status_code == 403
        assert "Access forbidden" in res.text

@pytest.mark.asyncio
async def test_student_cannot_review_action_approve():
    """Vulnerability #3 Fix: A student token calling /review-action must get 403 Forbidden."""
    student_token = create_access_token(user_id="student_123", role="student")
    headers = {"Authorization": f"Bearer {student_token}"}

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/documents/doc-12345/review-action",
            data={"action": "approve", "notes": "Self-approved"},
            headers=headers
        )
        assert res.status_code == 403
        assert "Access forbidden" in res.text

@pytest.mark.asyncio
async def test_student_cannot_replace_other_students_document(monkeypatch):
    """Vulnerability #6 Fix: A student cannot replace a document owned by another student."""
    from app.routers import documents as doc_router

    student_token = create_access_token(user_id="attacker_student", role="student")
    headers = {"Authorization": f"Bearer {student_token}"}

    other_student_doc = {
        "document_id": "victim_doc_id",
        "user_id": "victim_student",
        "student_id": "victim_student",
        "document_type": "TENTH_MARKSHEET"
    }
    monkeypatch.setattr(doc_router.verification_documents_collection, "find_one", AsyncMock(return_value=other_student_doc))

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        files = {"file": ("marksheet.png", b"fake image content", "image/png")}
        res = await ac.put("/documents/victim_doc_id/replace", files=files, headers=headers)
        assert res.status_code == 403
        assert "do not have permission" in res.text

@pytest.mark.asyncio
async def test_recruiter_cannot_edit_other_recruiters_drive(monkeypatch):
    """Vulnerability #7 Fix: Recruiter A cannot modify a drive posted by Recruiter B."""
    from app.routers import drives_recruiter as recruiter_router

    recruiter_a_token = create_access_token(user_id="recruiter_A", role="recruiter")
    headers = {"Authorization": f"Bearer {recruiter_a_token}"}

    drive_b = {
        "drive_id": "drive_of_company_b",
        "company_name": "Company B",
        "posted_by": "recruiter_B",
        "status": "published"
    }
    monkeypatch.setattr(recruiter_router.drives_collection, "find_one", AsyncMock(return_value=drive_b))

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.patch(
            "/recruiter/drives/drive_of_company_b",
            json={"description": "Hacked description"},
            headers=headers
        )
        assert res.status_code == 403
        assert "can only modify placement drives created by your account" in res.text

@pytest.mark.asyncio
async def test_file_download_idor_blocked(monkeypatch):
    """Vulnerability #5 Fix: Student A cannot download Student B's private file."""
    from app.routers import files as files_router

    student_a_token = create_access_token(user_id="student_A", role="student")
    headers = {"Authorization": f"Bearer {student_a_token}"}

    class MockGridOut:
        _id = "mock_grid_id"
        filename = "student_B_marksheet.pdf"
        metadata = {"user_id": "student_B", "student_id": "student_B", "content_type": "application/pdf"}
        async def read(self):
            return b"%PDF-1.4 mock content"

    monkeypatch.setattr(files_router, "_fetch_gridfs_stream", AsyncMock(return_value=MockGridOut()))
    monkeypatch.setattr(files_router.verification_documents_collection, "find_one", AsyncMock(return_value=None))
    monkeypatch.setattr(files_router.students_collection, "find_one", AsyncMock(return_value=None))
    monkeypatch.setattr(files_router.drives_collection, "find_one", AsyncMock(return_value=None))

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/api/v1/files/student_B_marksheet.pdf", headers=headers)
        assert res.status_code == 403
        assert "Access forbidden" in res.text

@pytest.mark.asyncio
async def test_unauthenticated_drives_list_is_eligible_false(monkeypatch):
    """Complexity/Bug Fix: Unauthenticated users see is_eligible=False instead of fake 8.0 CGPA."""
    from app.routers import drives_student as student_router

    mock_drive = {
        "drive_id": "drive_test_1",
        "company_name": "Google",
        "drive_title": "SWE",
        "min_cgpa": 7.0,
        "eligible_courses": ["BTECH_CSE"],
        "status": "published",
        "created_at": "2026-09-01T00:00:00Z"
    }
    mock_cursor = MagicMock()
    mock_cursor.sort.return_value = mock_cursor
    mock_cursor.skip.return_value = mock_cursor
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=[mock_drive])
    mock_find = MagicMock()
    mock_find.sort.return_value = mock_cursor
    monkeypatch.setattr(student_router.drives_collection, "find", lambda *args, **kwargs: mock_find)

    mock_comp_cursor = MagicMock()
    mock_comp_cursor.sort.return_value = mock_comp_cursor
    mock_comp_cursor.skip.return_value = mock_comp_cursor
    mock_comp_cursor.limit.return_value = mock_comp_cursor
    mock_comp_cursor.to_list = AsyncMock(return_value=[])
    mock_comp_find = MagicMock()
    mock_comp_find.sort.return_value = mock_comp_cursor
    monkeypatch.setattr(student_router.company_listings_collection, "find", lambda *args, **kwargs: mock_comp_find)

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/drives")
        assert res.status_code == 200
        items = res.json()["items"]
        assert len(items) > 0
        assert items[0]["is_eligible"] is False
