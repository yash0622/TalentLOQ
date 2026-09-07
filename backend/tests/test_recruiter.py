import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.mark.asyncio
async def test_recruiter_company_endpoints_unauthorized():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        res = await client.get("/recruiter/companies")
        assert res.status_code in (401, 403)

        res = await client.get("/recruiter/stats")
        assert res.status_code in (401, 403)

        res = await client.get("/recruiter/companies/dummy-id/applicants")
        assert res.status_code in (401, 403)

@pytest.mark.asyncio
async def test_announcements_public_endpoint(monkeypatch):
    import app.routers.announcements as ann_router
    class MockCursor:
        async def to_list(self, length):
            return [{
                "announcement_id": "ann-1",
                "title": "Welcome Drive",
                "content": "Campus placement drive starts tomorrow.",
                "author_email": "recruiter@talentloq.com",
                "created_at": "2026-08-10T10:00:00Z",
            }]
        def sort(self, *args, **kwargs):
            return self

    monkeypatch.setattr(ann_router.announcements_collection, "find", lambda q: MockCursor())

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        res = await client.get("/announcements")
        assert res.status_code == 200
        data = res.json()
        assert "announcements" in data
        assert "count" in data

@pytest.mark.asyncio
async def test_company_listings_full_lifecycle(monkeypatch):
    from unittest.mock import AsyncMock, MagicMock
    from app.jwt_utils import create_access_token
    import app.routers.recruiter as recruiter_router

    mock_db_store = {}

    async def mock_insert_one(doc):
        listing_id = doc.get("listing_id")
        if listing_id:
            mock_db_store[listing_id] = dict(doc)
        return MagicMock(inserted_id="mock_id")

    async def mock_find_one(query):
        listing_id = query.get("listing_id")
        if listing_id and listing_id in mock_db_store:
            return dict(mock_db_store[listing_id])
        return None

    async def mock_update_one(query, update):
        listing_id = query.get("listing_id")
        if listing_id and listing_id in mock_db_store:
            mock_db_store[listing_id].update(update.get("$set", {}))
        return MagicMock(modified_count=1)

    class MockCursor:
        def __init__(self, data):
            self._data = data
        def sort(self, *args, **kwargs):
            return self
        async def to_list(self, length):
            return self._data

    def mock_find(query):
        return MockCursor(list(mock_db_store.values()))

    async def mock_count_documents(query):
        return len(mock_db_store)

    monkeypatch.setattr(recruiter_router.company_listings_collection, "insert_one", mock_insert_one)
    monkeypatch.setattr(recruiter_router.company_listings_collection, "find_one", mock_find_one)
    monkeypatch.setattr(recruiter_router.company_listings_collection, "update_one", mock_update_one)
    monkeypatch.setattr(recruiter_router.company_listings_collection, "find", mock_find)
    monkeypatch.setattr(recruiter_router.company_listings_collection, "count_documents", mock_count_documents)
    monkeypatch.setattr(recruiter_router.drives_collection, "count_documents", AsyncMock(return_value=0))
    monkeypatch.setattr(recruiter_router.drives_collection, "find", lambda q: MockCursor([]))
    monkeypatch.setattr(recruiter_router.drives_collection, "insert_one", AsyncMock())
    monkeypatch.setattr(recruiter_router.drives_collection, "update_one", AsyncMock())
    monkeypatch.setattr(recruiter_router.audit_logs_collection, "insert_one", AsyncMock())
    monkeypatch.setattr(recruiter_router.applications_collection, "count_documents", AsyncMock(return_value=2))
    monkeypatch.setattr(recruiter_router.applications_collection, "find", lambda q: MockCursor([{"app_id": "app-1", "student_id": "s-1", "meets_cgpa_criteria": True}]))
    monkeypatch.setattr(recruiter_router.students_collection, "count_documents", AsyncMock(return_value=150))
    monkeypatch.setattr(recruiter_router.students_collection, "find_one", AsyncMock(return_value={"full_name": "Test Student", "CGPA": 8.5}))

    recruiter_token = create_access_token(user_id="test-recruiter-uuid", role="recruiter")
    headers = {"Authorization": f"Bearer {recruiter_token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        # 1. Create company listing
        form_data = {
            "company_name": "Tech Corp",
            "company_email": "hr@techcorp.com",
            "description": "Leading software engineer role.",
            "interview_job": "Senior Software Engineer",
            "bond_time": "1 year",
            "interview_datetime": "Aug 25, 2026 at 10:00 AM",
            "interview_venue": "GSFC Auditorium",
            "cgpa_criteria": "7.5",
        }
        res = await client.post("/recruiter/companies", data=form_data, headers=headers)
        assert res.status_code == 201
        created = res.json()
        assert created["company_name"] == "Tech Corp"
        assert created["status"] == "draft"
        listing_id = created["listing_id"]

        # 2. Patch edit company listing
        patch_payload = {"description": "Updated job description.", "status": "published"}
        res = await client.patch(f"/recruiter/companies/{listing_id}", json=patch_payload, headers=headers)
        assert res.status_code == 200
        patched = res.json()
        assert patched["description"] == "Updated job description."
        assert patched["status"] == "published"

        # 3. Publish company listing
        res = await client.post(f"/recruiter/companies/{listing_id}/publish", headers=headers)
        assert res.status_code == 200
        published_res = res.json()
        assert published_res["listing"]["status"] == "published"

        # 4. List recruiter companies
        res = await client.get("/recruiter/companies", headers=headers)
        assert res.status_code == 200
        listings = res.json()
        assert isinstance(listings, list)
        assert len(listings) >= 1
        assert "applicant_count" in listings[0]

        # 5. List applicants
        res = await client.get(f"/recruiter/companies/{listing_id}/applicants", headers=headers)
        assert res.status_code == 200
        applicants = res.json()
        assert isinstance(applicants, list)
        assert len(applicants) == 1
        assert applicants[0]["name"] == "Test Student"

        # 6. Recruiter Stats
        res = await client.get("/recruiter/stats", headers=headers)
        assert res.status_code == 200
        stats = res.json()
        assert stats["total_registered_students"] == 150
        assert stats["total_active_listings"] == 1


@pytest.mark.asyncio
async def test_list_recruiter_company_listings_fallback_to_drives(monkeypatch):
    from unittest.mock import AsyncMock
    from app.jwt_utils import create_access_token
    import app.routers.recruiter as recruiter_router

    class MockCursor:
        def __init__(self, data):
            self._data = data
        def sort(self, *args, **kwargs):
            return self
        async def to_list(self, length):
            return self._data

    # Empty company listings, so it falls back to drives_collection
    monkeypatch.setattr(recruiter_router.company_listings_collection, "find", lambda q: MockCursor([]))
    monkeypatch.setattr(recruiter_router.drives_collection, "find", lambda q: MockCursor([
        {"drive_id": "drive-101", "drive_title": "Frontend Lead", "min_cgpa": 7.0}
    ]))
    monkeypatch.setattr(recruiter_router.applications_collection, "count_documents", AsyncMock(return_value=5))

    recruiter_token = create_access_token(user_id="test-recruiter-uuid", role="recruiter")
    headers = {"Authorization": f"Bearer {recruiter_token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        res = await client.get("/recruiter/companies", headers=headers)
        assert res.status_code == 200
        listings = res.json()
        assert len(listings) == 1
        assert listings[0]["listing_id"] == "drive-101"
        assert listings[0]["interview_job"] == "Frontend Lead"
        assert listings[0]["applicant_count"] == 5



