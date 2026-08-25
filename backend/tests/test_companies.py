import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.mark.asyncio
async def test_list_published_companies(monkeypatch):
    import app.routers.companies as companies_router
    class MockCursor:
        async def to_list(self, length):
            return [{
                "listing_id": "c-1",
                "company_name": "Google",
                "description": "Tech giant software engineer position.",
                "cgpa_criteria": 7.0,
                "interview_job": "SDE-1",
                "status": "published",
            }]
        def sort(self, *args, **kwargs):
            return self

    class MockEmptyCursor:
        async def to_list(self, length):
            return []
        def sort(self, *args, **kwargs):
            return self

    monkeypatch.setattr(companies_router.company_listings_collection, "find", lambda q: MockCursor())
    monkeypatch.setattr(companies_router.drives_collection, "find", lambda q: MockEmptyCursor())

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        res = await client.get("/companies")
        assert res.status_code == 200
        listings = res.json()
        assert isinstance(listings, list)
        assert len(listings) == 1
        assert listings[0]["company_name"] == "Google"

@pytest.mark.asyncio
async def test_apply_to_company_listing_full_flow(monkeypatch):
    from unittest.mock import AsyncMock, MagicMock
    from app.jwt_utils import create_access_token
    import app.routers.companies as companies_router

    mock_listings = {
        "list-101": {
            "listing_id": "list-101",
            "company_name": "Google India",
            "interview_job": "Software Engineer",
            "cgpa_criteria": 7.5,
            "status": "published",
        }
    }
    mock_applications = {}
    mock_students = {
        "student-uuid-123": {
            "student_id": "student-uuid-123",
            "user_id": "student-uuid-123",
            "full_name": "Student Alpha",
            "CGPA": 8.2,
            "has_resume": True,
            "resume_id": "res_v1_pdf",
        }
    }

    async def mock_find_one_listing(query):
        lid = query.get("listing_id")
        return mock_listings.get(lid)

    async def mock_find_one_student(query):
        return mock_students.get("student-uuid-123")

    async def mock_find_one_app(query):
        lid = query.get("listing_id")
        return mock_applications.get(lid)

    async def mock_insert_app(doc):
        lid = doc.get("listing_id")
        mock_applications[lid] = doc
        return MagicMock(inserted_id="app_id")

    monkeypatch.setattr(companies_router.company_listings_collection, "find_one", mock_find_one_listing)
    monkeypatch.setattr(companies_router.students_collection, "find_one", mock_find_one_student)
    monkeypatch.setattr(companies_router.applications_collection, "find_one", mock_find_one_app)
    monkeypatch.setattr(companies_router.applications_collection, "insert_one", mock_insert_app)
    monkeypatch.setattr(companies_router.audit_logs_collection, "insert_one", AsyncMock())

    student_token = create_access_token(user_id="student-uuid-123", role="student")
    headers = {"Authorization": f"Bearer {student_token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        # 1. Get Detail
        res = await client.get("/companies/list-101")
        assert res.status_code == 200
        detail = res.json()
        assert detail["company_name"] == "Google India"

        # 2. Apply to listing
        res = await client.post("/companies/list-101/apply", headers=headers)
        assert res.status_code == 201
        applied = res.json()
        assert applied["application"]["meets_cgpa_criteria"] is True
        assert applied["application"]["status"] == "applied"

        # 3. Duplicate Application should return 409
        res = await client.post("/companies/list-101/apply", headers=headers)
        assert res.status_code == 409
        assert "already submitted" in res.json()["detail"].lower()
