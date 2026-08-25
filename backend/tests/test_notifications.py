import pytest
from unittest.mock import AsyncMock, MagicMock
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.jwt_utils import create_access_token
from app.notifications import notify_on_publish, notify_on_schedule_change

@pytest.mark.asyncio
async def test_notify_on_publish_all_audience(monkeypatch):
    import app.notifications as notif_module

    mock_listing = {
        "listing_id": "listing-pub-1",
        "company_name": "Google",
        "interview_job": "SDE-1",
        "cgpa_criteria": 7.5,
        "status": "published",
    }
    mock_students = [
        {"student_id": "s-1", "email": "s1@test.com", "CGPA": 8.5, "fcm_token": "token-1"},
        {"student_id": "s-2", "email": "s2@test.com", "CGPA": 6.8, "fcm_token": "token-2"},
    ]

    class MockCursor:
        async def to_list(self, length):
            return mock_students

    monkeypatch.setattr(notif_module.company_listings_collection, "find_one", AsyncMock(return_value=mock_listing))
    monkeypatch.setattr(notif_module.students_collection, "find", lambda query: MockCursor())
    monkeypatch.setattr(notif_module.notifications_collection, "insert_one", AsyncMock())

    # Test audience="all" -> should notify both students (2)
    res = await notify_on_publish("listing-pub-1", target_audience="all")
    assert res["status"] == "success"
    assert res["notified_count"] == 2
    assert res["target_audience"] == "all"

@pytest.mark.asyncio
async def test_notify_on_publish_eligible_only_audience(monkeypatch):
    import app.notifications as notif_module

    mock_listing = {
        "listing_id": "listing-pub-2",
        "company_name": "Microsoft",
        "interview_job": "Software Engineer",
        "cgpa_criteria": 7.5,
        "status": "published",
    }
    mock_students = [
        {"student_id": "s-1", "email": "s1@test.com", "CGPA": 8.5, "fcm_token": "token-1"},
        {"student_id": "s-2", "email": "s2@test.com", "CGPA": 6.8, "fcm_token": "token-2"},
    ]

    class MockCursor:
        async def to_list(self, length):
            return mock_students

    monkeypatch.setattr(notif_module.company_listings_collection, "find_one", AsyncMock(return_value=mock_listing))
    monkeypatch.setattr(notif_module.students_collection, "find", lambda query: MockCursor())
    monkeypatch.setattr(notif_module.notifications_collection, "insert_one", AsyncMock())

    # Test audience="eligible_only" -> only s-1 (CGPA 8.5 >= 7.5) should be notified (1)
    res = await notify_on_publish("listing-pub-2", target_audience="eligible_only")
    assert res["status"] == "success"
    assert res["notified_count"] == 1
    assert res["target_audience"] == "eligible_only"

@pytest.mark.asyncio
async def test_notify_on_schedule_change(monkeypatch):
    import app.notifications as notif_module

    mock_listing = {
        "listing_id": "listing-pub-3",
        "company_name": "Amazon",
        "interview_job": "Cloud Architect",
        "interview_datetime": "Aug 25, 2026 • 10:00 AM",
        "interview_venue": "Campus Auditorium Hall B",
        "status": "published",
    }
    mock_apps = [
        {"app_id": "app-1", "listing_id": "listing-pub-3", "student_id": "s-1"},
        {"app_id": "app-2", "listing_id": "listing-pub-3", "student_id": "s-3"},
    ]

    class MockAppCursor:
        async def to_list(self, length):
            return mock_apps

    monkeypatch.setattr(notif_module.company_listings_collection, "find_one", AsyncMock(return_value=mock_listing))
    monkeypatch.setattr(notif_module.applications_collection, "find", lambda query: MockAppCursor())
    monkeypatch.setattr(notif_module.students_collection, "find_one", AsyncMock(return_value={"student_id": "s-1", "email": "s1@test.com"}))
    monkeypatch.setattr(notif_module.notifications_collection, "insert_one", AsyncMock())

    res = await notify_on_schedule_change("listing-pub-3")
    assert res["status"] == "success"
    assert res["notified_count"] == 2
