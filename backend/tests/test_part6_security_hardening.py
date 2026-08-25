import pytest
from unittest.mock import AsyncMock, MagicMock
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.jwt_utils import create_access_token

@pytest.mark.asyncio
async def test_student_jwt_rejected_on_recruiter_endpoints():
    student_token = create_access_token(user_id="student-123", role="student")
    headers = {"Authorization": f"Bearer {student_token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        # GET /recruiter/companies -> 403
        res = await client.get("/recruiter/companies", headers=headers)
        assert res.status_code == 403
        assert "Access forbidden" in res.json()["detail"]

        # GET /recruiter/stats -> 403
        res = await client.get("/recruiter/stats", headers=headers)
        assert res.status_code == 403

        # POST /recruiter/companies -> 403
        res = await client.post("/recruiter/companies", data={"company_name": "Test"}, headers=headers)
        assert res.status_code == 403

        # PATCH /recruiter/companies/dummy-id -> 403
        res = await client.patch("/recruiter/companies/dummy-id", json={"status": "published"}, headers=headers)
        assert res.status_code == 403

        # POST /recruiter/companies/dummy-id/publish -> 403
        res = await client.post("/recruiter/companies/dummy-id/publish", headers=headers)
        assert res.status_code == 403

@pytest.mark.asyncio
async def test_non_pdf_file_upload_rejected(monkeypatch):
    import app.routers.recruiter as recruiter_router

    monkeypatch.setattr(recruiter_router.company_listings_collection, "insert_one", AsyncMock())
    monkeypatch.setattr(recruiter_router.audit_logs_collection, "insert_one", AsyncMock())

    recruiter_token = create_access_token(user_id="recruiter-uuid-001", role="recruiter")
    headers = {"Authorization": f"Bearer {recruiter_token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        # Test 1: Wrong file extension (.exe)
        files = {"pdf": ("malicious.exe", b"binary data", "application/x-msdownload")}
        data = {
            "company_name": "Malicious Corp",
            "company_email": "hr@malicious.com",
            "description": "Bad file test",
            "interview_job": "Tester",
            "interview_datetime": "Tomorrow",
            "interview_venue": "Online",
        }
        res = await client.post("/recruiter/companies", data=data, files=files, headers=headers)
        assert res.status_code == 400
        assert "PDF document" in res.json()["detail"]

        # Test 2: .pdf extension but invalid magic bytes header
        fake_pdf = {"pdf": ("fake.pdf", b"NOT_A_REAL_PDF_HEADER", "application/pdf")}
        res = await client.post("/recruiter/companies", data=data, files=fake_pdf, headers=headers)
        assert res.status_code == 400
        assert "Invalid PDF file header" in res.json()["detail"]

@pytest.mark.asyncio
async def test_draft_listing_not_visible_to_students(monkeypatch):
    import app.routers.companies as companies_router

    class MockCursor:
        async def to_list(self, length):
            # Only published listings should be returned when status="published" query is executed
            return [{
                "listing_id": "pub-001",
                "company_name": "Published Tech",
                "interview_job": "SDE",
                "status": "published",
            }]
        def sort(self, *args, **kwargs):
            return self

    class MockEmptyCursor:
        async def to_list(self, length):
            return []
        def sort(self, *args, **kwargs):
            return self

    def mock_find(query):
        assert query == {"status": "published"}
        return MockCursor()

    monkeypatch.setattr(companies_router.company_listings_collection, "find", mock_find)
    monkeypatch.setattr(companies_router.drives_collection, "find", lambda q: MockEmptyCursor())

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        res = await client.get("/companies")
        assert res.status_code == 200
        listings = res.json()
        assert len(listings) == 1
        assert listings[0]["company_name"] == "Published Tech"

@pytest.mark.asyncio
async def test_duplicate_application_returns_409(monkeypatch):
    import app.routers.companies as companies_router

    mock_listing = {"listing_id": "listing-999", "cgpa_criteria": 6.0}
    mock_student = {"student_id": "student-777", "user_id": "student-777", "CGPA": 8.0, "has_resume": True}
    mock_existing_app = {"app_id": "existing-app-1", "listing_id": "listing-999", "student_id": "student-777"}

    async def mock_find_one_listing(query):
        return mock_listing

    async def mock_find_one_student(query):
        return mock_student

    async def mock_find_one_app(query):
        return mock_existing_app

    monkeypatch.setattr(companies_router.company_listings_collection, "find_one", mock_find_one_listing)
    monkeypatch.setattr(companies_router.students_collection, "find_one", mock_find_one_student)
    monkeypatch.setattr(companies_router.applications_collection, "find_one", mock_find_one_app)

    student_token = create_access_token(user_id="student-777", role="student")
    headers = {"Authorization": f"Bearer {student_token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        res = await client.post("/companies/listing-999/apply", headers=headers)
        assert res.status_code == 409
        assert "already submitted" in res.json()["detail"].lower()

@pytest.mark.asyncio
async def test_audit_logs_written_for_all_mutating_actions(monkeypatch):
    import app.routers.recruiter as recruiter_router
    import app.routers.companies as companies_router

    audit_logs = []

    async def mock_insert_audit(doc):
        audit_logs.append(doc)
        return MagicMock(inserted_id="audit_id")

    mock_db_store = {
        "listing-test": {
            "listing_id": "listing-test",
            "company_name": "Audit Company",
            "status": "draft",
            "cgpa_criteria": 6.0,
        }
    }

    async def mock_find_one_recruiter(query):
        lid = query.get("listing_id")
        return mock_db_store.get(lid)

    async def mock_update_one(query, update):
        lid = query.get("listing_id")
        if lid in mock_db_store:
            mock_db_store[lid].update(update.get("$set", {}))
        return MagicMock(modified_count=1)

    monkeypatch.setattr(recruiter_router.audit_logs_collection, "insert_one", mock_insert_audit)
    monkeypatch.setattr(recruiter_router.company_listings_collection, "insert_one", AsyncMock())
    monkeypatch.setattr(recruiter_router.company_listings_collection, "find_one", mock_find_one_recruiter)
    monkeypatch.setattr(recruiter_router.company_listings_collection, "update_one", mock_update_one)

    monkeypatch.setattr(companies_router.audit_logs_collection, "insert_one", mock_insert_audit)
    monkeypatch.setattr(companies_router.company_listings_collection, "find_one", mock_find_one_recruiter)
    monkeypatch.setattr(companies_router.students_collection, "find_one", AsyncMock(return_value={"student_id": "s-1", "has_resume": True, "CGPA": 8.0}))
    monkeypatch.setattr(companies_router.applications_collection, "find_one", AsyncMock(return_value=None))
    monkeypatch.setattr(companies_router.applications_collection, "insert_one", AsyncMock())

    recruiter_token = create_access_token(user_id="recruiter-uuid-001", role="recruiter")
    student_token = create_access_token(user_id="student-uuid-002", role="student")

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        # 1. Recruiter Create
        data = {
            "company_name": "Audit Company",
            "company_email": "audit@company.com",
            "description": "Audit testing",
            "interview_job": "Engineer",
            "interview_datetime": "Tomorrow",
            "interview_venue": "Campus",
        }
        res = await client.post("/recruiter/companies", data=data, headers={"Authorization": f"Bearer {recruiter_token}"})
        assert res.status_code == 201

        # 2. Recruiter Edit
        res = await client.patch("/recruiter/companies/listing-test", json={"description": "New description"}, headers={"Authorization": f"Bearer {recruiter_token}"})
        assert res.status_code == 200

        # 3. Recruiter Publish
        res = await client.post("/recruiter/companies/listing-test/publish", headers={"Authorization": f"Bearer {recruiter_token}"})
        assert res.status_code == 200

        # 4. Student Apply
        res = await client.post("/companies/listing-test/apply", headers={"Authorization": f"Bearer {student_token}"})
        assert res.status_code == 201

    # Verify 4 audit logs were captured with expected actions
    actions_recorded = [log.get("action") for log in audit_logs]
    assert "RECRUITER_COMPANY_LISTING_CREATED" in actions_recorded
    assert "RECRUITER_COMPANY_LISTING_EDITED" in actions_recorded
    assert "RECRUITER_COMPANY_LISTING_PUBLISHED" in actions_recorded
    assert "STUDENT_COMPANY_APPLICATION_SUBMITTED" in actions_recorded
