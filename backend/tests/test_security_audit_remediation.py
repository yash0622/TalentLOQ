import pytest
from unittest.mock import AsyncMock, patch
from httpx import AsyncClient, ASGITransport
from pathlib import Path

from app.main import app
from app.config import settings
from app.security import scrub_pii, sanitize_text, hash_password
from app.jwt_utils import create_access_token
from app.encryption import decrypt_field

def test_scrub_pii_removes_contacts():
    raw_text = "Contact Alice at alice.smith@example.com or call +91 9876543210 for details."
    scrubbed = scrub_pii(raw_text)
    assert "alice.smith@example.com" not in scrubbed
    assert "9876543210" not in scrubbed
    assert "[REDACTED_EMAIL]" in scrubbed
    assert "[REDACTED_PHONE]" in scrubbed

def test_sanitize_text_removes_scripts_and_html():
    malicious = "<script>alert('pwned')</script><b>Hello</b>\x00\x07World"
    clean = sanitize_text(malicious)
    assert "<script>" not in clean
    assert "<b>" not in clean
    assert clean == "HelloWorld"

def test_access_token_expire_default_is_15_minutes():
    assert settings.ACCESS_TOKEN_EXPIRE_MINUTES == 15

def test_android_flag_secure_enabled():
    main_activity_path = Path("../android/app/src/main/kotlin/com/example/talentloq/MainActivity.kt")
    assert main_activity_path.exists(), "MainActivity.kt must exist"
    content = main_activity_path.read_text(encoding="utf-8")
    assert "FLAG_SECURE" in content, "FLAG_SECURE must be enabled in MainActivity"
    assert "window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)" in content

@pytest.mark.asyncio
async def test_chat_message_sanitization(monkeypatch):
    from app.routers import chat as chat_router

    monkeypatch.setattr(chat_router.chat_messages_collection, "insert_one", AsyncMock())
    monkeypatch.setattr(chat_router.students_collection, "find_one", AsyncMock(return_value={"full_name": "Test Student"}))
    student_token = create_access_token(user_id="student_user_1", role="student")
    headers = {"Authorization": f"Bearer {student_token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Message with script tag and html
        res = await ac.post("/chat/messages", json={
            "recipient_id": "recruiter_user_2",
            "text": "<script>alert('xss')</script>Hello Recruiter!<b>bold</b>"
        }, headers=headers)
        assert res.status_code == 201
        data = res.json()
        assert "<script>" not in data["text"]
        assert "<b>" not in data["text"]
        assert data["text"] == "Hello Recruiter!bold"

        # Message with ONLY malicious content gets rejected as empty
        empty_res = await ac.post("/chat/messages", json={
            "recipient_id": "recruiter_user_2",
            "text": "<script>alert(1)</script>"
        }, headers=headers)
        assert empty_res.status_code == 400
        assert "cannot be empty" in empty_res.text

@pytest.mark.asyncio
async def test_change_password_endpoint_flow(monkeypatch):
    from app.routers import auth as auth_router

    user_id = "test_user_for_pw_change"
    initial_pw = "OldPassword123!"
    stored_user = {
        "user_id": user_id,
        "email": "user@gsfcuniversity.ac.in",
        "password_hash": hash_password(initial_pw),
        "role": "student",
        "must_change_password": True,
    }

    mock_update_user = AsyncMock()
    mock_update_tokens = AsyncMock()
    mock_insert_audit = AsyncMock()

    monkeypatch.setattr(auth_router.users_collection, "find_one", AsyncMock(return_value=stored_user))
    monkeypatch.setattr(auth_router.users_collection, "update_one", mock_update_user)
    monkeypatch.setattr(auth_router.refresh_tokens_collection, "update_many", mock_update_tokens)
    monkeypatch.setattr(auth_router.audit_logs_collection, "insert_one", mock_insert_audit)

    token = create_access_token(user_id=user_id, role="student")
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Wrong old password
        res_fail = await ac.post("/auth/change-password", json={
            "old_password": "WrongPassword!",
            "new_password": "BrandNewPassword2026!"
        }, headers=headers)
        assert res_fail.status_code == 400
        assert "Incorrect current password" in res_fail.text

        # 2. Short new password (<8 chars)
        res_short = await ac.post("/auth/change-password", json={
            "old_password": initial_pw,
            "new_password": "short"
        }, headers=headers)
        assert res_short.status_code == 422

        # 3. Successful password change
        res_ok = await ac.post("/auth/change-password", json={
            "old_password": initial_pw,
            "new_password": "BrandNewPassword2026!"
        }, headers=headers)
        assert res_ok.status_code == 200
        assert "Password changed successfully" in res_ok.text

        # Verify DB updates and token revocation
        assert mock_update_user.called
        assert mock_update_tokens.called
        assert mock_insert_audit.called

@pytest.mark.asyncio
async def test_update_profile_phone_encryption_and_audit(monkeypatch):
    from app.routers import auth as auth_router

    user_id = "std_phone_test_1"
    user_doc = {
        "user_id": user_id,
        "email": "phone_test@gsfcuniversity.ac.in",
        "full_name": "Test Student",
        "role": "student",
    }

    mock_students_update = AsyncMock()
    mock_audit_insert = AsyncMock()

    monkeypatch.setattr(auth_router.users_collection, "find_one", AsyncMock(return_value=user_doc))
    monkeypatch.setattr(auth_router.users_collection, "update_many", AsyncMock())
    monkeypatch.setattr(auth_router.students_collection, "update_many", mock_students_update)
    monkeypatch.setattr(auth_router.audit_logs_collection, "insert_one", mock_audit_insert)

    token = create_access_token(user_id=user_id, role="student")
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.put("/auth/me", json={
            "full_name": "Test Student Updated",
            "phone_number": "+91 9876543210"
        }, headers=headers)
        assert res.status_code == 200

        # Check that update_many was called with encrypted_phone
        assert mock_students_update.called
        call_args = mock_students_update.call_args[0]
        update_dict = call_args[1]["$set"]
        assert update_dict["phone_number"] == "+91 9876543210"
        assert "encrypted_phone" in update_dict
        # Verify it can be decrypted back to original
        assert decrypt_field(update_dict["encrypted_phone"]) == "+91 9876543210"

        # Check audit log was inserted
        assert mock_audit_insert.called
        audit_doc = mock_audit_insert.call_args[0][0]
        assert audit_doc["action"] == "STUDENT_PROFILE_UPDATE"
        assert audit_doc["user_id"] == user_id

@pytest.mark.asyncio
async def test_document_download_audit(monkeypatch):
    from app.routers import files as files_router

    mock_audit_insert = AsyncMock()
    monkeypatch.setattr(files_router.audit_logs_collection, "insert_one", mock_audit_insert)

    class MockGridFile:
        def __init__(self):
            self.filename = "safe_resume.pdf"
            self.metadata = {"content_type": "application/pdf", "user_id": "test_user_download"}
            self._id = "mock_grid_id_123"

        async def read(self):
            return b"%PDF-1.4 dummy pdf data"

    monkeypatch.setattr(files_router, "_fetch_gridfs_stream", AsyncMock(return_value=MockGridFile()))

    token = create_access_token(user_id="test_user_download", role="student")
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/api/v1/files/mock_grid_id_123", headers=headers)
        assert res.status_code == 200
        assert mock_audit_insert.called
        audit_call = mock_audit_insert.call_args[0][0]
        assert audit_call["action"] == "DOCUMENT_DOWNLOAD"
        assert audit_call["user_id"] == "test_user_download"

