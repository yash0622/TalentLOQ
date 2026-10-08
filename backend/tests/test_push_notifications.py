import pytest
from datetime import datetime, timezone, timedelta
import motor.motor_asyncio
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.config import settings
from app.jwt_utils import create_access_token
import app.database as db
import app.services.push_notification_service as push_service
import app.routers.notifications as notif_router
from app.services.push_notification_service import (
    notify,
    _filter_users_by_preference,
    _deduplicate_users,
)
from app.eligibility import compute_eligibility


@pytest.fixture(autouse=True)
def bind_test_motor():
    """Ensure Motor collections are bound to current test's running event loop."""
    client = motor.motor_asyncio.AsyncIOMotorClient(settings.MONGODB_URL)
    test_db = client[settings.DATABASE_NAME]
    
    db.device_tokens_collection = test_db["device_tokens"]
    db.notifications_collection = test_db["notifications"]
    db.notification_preferences_collection = test_db["notification_preferences"]
    
    push_service.device_tokens_collection = test_db["device_tokens"]
    push_service.notifications_collection = test_db["notifications"]
    push_service.notification_preferences_collection = test_db["notification_preferences"]
    
    notif_router.device_tokens_collection = test_db["device_tokens"]
    notif_router.notifications_collection = test_db["notifications"]
    notif_router.notification_preferences_collection = test_db["notification_preferences"]


@pytest.fixture
def auth_headers():
    token = create_access_token(user_id="student-test-123", role="student")
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def other_user_headers():
    token = create_access_token(user_id="student-other-456", role="student")
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.asyncio
async def test_device_token_register_refresh_and_delete(auth_headers, other_user_headers):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # 1. Register token for user 1
        res = await ac.post(
            "/notifications/device-token",
            headers=auth_headers,
            json={"token": "test-fcm-token-abc", "platform": "android", "app_version": "1.0.1"},
        )
        assert res.status_code == 200
        assert res.json()["status"] == "ok"

        # Check DB
        doc = await db.device_tokens_collection.find_one({"token": "test-fcm-token-abc"})
        assert doc is not None
        assert doc["user_id"] == "student-test-123"
        assert doc["platform"] == "android"

        # 2. Reassign token to user 2 (e.g. device switch/relogin)
        res = await ac.post(
            "/notifications/device-token",
            headers=other_user_headers,
            json={"token": "test-fcm-token-abc", "platform": "android", "app_version": "1.0.2"},
        )
        assert res.status_code == 200

        doc_reassigned = await db.device_tokens_collection.find_one({"token": "test-fcm-token-abc"})
        assert doc_reassigned["user_id"] == "student-other-456"

        # 3. Delete token on logout
        del_res = await ac.delete(
            "/notifications/device-token?token=test-fcm-token-abc",
            headers=other_user_headers,
        )
        assert del_res.status_code == 200
        assert del_res.json()["deleted_count"] >= 1

        doc_after_del = await db.device_tokens_collection.find_one({"token": "test-fcm-token-abc"})
        assert doc_after_del is None


@pytest.mark.asyncio
async def test_invalid_token_pruning(monkeypatch):
    # Clean prior test tokens
    await db.device_tokens_collection.delete_many({"token": {"$in": ["dead-token-1", "valid-token-1"]}})
    # Insert test tokens
    await db.device_tokens_collection.insert_one(
        {"token": "dead-token-1", "user_id": "u-dead-1", "platform": "android", "created_at": datetime.now(timezone.utc)}
    )
    await db.device_tokens_collection.insert_one(
        {"token": "valid-token-1", "user_id": "u-valid-1", "platform": "android", "created_at": datetime.now(timezone.utc)}
    )

    # Mock send_multicast_fcm to report dead-token-1 as invalid
    def mock_send(tokens, title, body, data):
        dead = [t for t in tokens if "dead" in t]
        return len(tokens) - len(dead), dead

    monkeypatch.setattr(push_service, "send_multicast_fcm", mock_send)

    # Run dispatch worker directly
    await push_service._dispatch_push_worker(
        target_users=["u-dead-1", "u-valid-1"],
        title="Test Title",
        body="Test Body",
        data={"type": "test"},
    )

    # Verify dead-token-1 was pruned from DB
    dead_in_db = await db.device_tokens_collection.find_one({"token": "dead-token-1"})
    assert dead_in_db is None

    # Valid token remains
    valid_in_db = await db.device_tokens_collection.find_one({"token": "valid-token-1"})
    assert valid_in_db is not None

    # Clean up
    await db.device_tokens_collection.delete_many({"token": {"$in": ["dead-token-1", "valid-token-1"]}})


@pytest.mark.asyncio
async def test_eligible_only_targeting():
    drive = {
        "drive_id": "drive-tech-99",
        "company_name": "Tech Corp",
        "min_cgpa": 7.5,
        "eligible_courses": ["CSE", "IT"],
        "max_backlogs": 0,
    }

    eligible_student = {
        "student_id": "st-elig",
        "cgpa": 8.2,
        "branch": "Computer Science & Engineering",
        "active_backlogs": 0,
    }

    ineligible_low_cgpa = {
        "student_id": "st-inelig-1",
        "cgpa": 7.1,
        "branch": "CSE",
        "active_backlogs": 0,
    }

    ineligible_backlogs = {
        "student_id": "st-inelig-2",
        "cgpa": 8.5,
        "branch": "IT",
        "active_backlogs": 2,
    }

    ineligible_branch = {
        "student_id": "st-inelig-3",
        "cgpa": 9.0,
        "branch": "Civil Engineering",
        "active_backlogs": 0,
    }

    assert compute_eligibility(eligible_student, drive) is True
    assert compute_eligibility(ineligible_low_cgpa, drive) is False
    assert compute_eligibility(ineligible_backlogs, drive) is False
    assert compute_eligibility(ineligible_branch, drive) is False


@pytest.mark.asyncio
async def test_deduplication():
    user_id = "user-dedup-test"
    entity_id = "drive-dedup-101"
    notif_type = "drive_published"

    # Clean prior test state
    await db.notifications_collection.delete_many({"user_id": user_id})

    # First send -> should not be deduplicated
    unfiltered = await _deduplicate_users([user_id], notif_type, {"drive_id": entity_id})
    assert user_id in unfiltered

    # Insert notification into DB simulating first delivery
    await db.notifications_collection.insert_one({
        "user_id": user_id,
        "type": notif_type,
        "title": "Drive Published",
        "body": "Check it out",
        "data": {"drive_id": entity_id, "entity_id": entity_id},
        "read": False,
        "created_at": datetime.now(timezone.utc),
    })

    # Second send with same entity_id -> should be filtered out by dedup
    filtered = await _deduplicate_users([user_id], notif_type, {"drive_id": entity_id})
    assert user_id not in filtered

    # Clean up
    await db.notifications_collection.delete_many({"user_id": user_id})


@pytest.mark.asyncio
async def test_preference_opt_out():
    user_opted_out = "user-opt-out-drives"
    user_opted_in = "user-opt-in-drives"

    # Set user preference opting out of drive_alerts
    await db.notification_preferences_collection.update_one(
        {"user_id": user_opted_out},
        {"$set": {"drive_alerts": False, "round_results": True}},
        upsert=True,
    )
    await db.notification_preferences_collection.update_one(
        {"user_id": user_opted_in},
        {"$set": {"drive_alerts": True, "round_results": True}},
        upsert=True,
    )

    recipients = [user_opted_out, user_opted_in]
    filtered_for_drives = await _filter_users_by_preference(recipients, "drive_published")

    assert user_opted_out not in filtered_for_drives
    assert user_opted_in in filtered_for_drives

    # Clean up
    await db.notification_preferences_collection.delete_many({"user_id": {"$in": recipients}})


@pytest.mark.asyncio
async def test_inbox_pagination_and_read_markers(auth_headers):
    user_id = "student-test-123"
    await db.notifications_collection.delete_many({"user_id": user_id})

    now = datetime.now(timezone.utc)
    test_docs = []
    for i in range(15):
        test_docs.append({
            "notification_id": f"notif-page-{i}",
            "user_id": user_id,
            "type": "drive_published",
            "title": f"Notification #{i}",
            "body": f"Details for item {i}",
            "data": {"drive_id": f"d-{i}"},
            "read": False,
            "created_at": now - timedelta(minutes=i),
        })
    await db.notifications_collection.insert_many(test_docs)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # 1. Unread count check
        unread_res = await ac.get("/notifications/unread-count", headers=auth_headers)
        assert unread_res.status_code == 200
        assert unread_res.json()["unread_count"] == 15

        # 2. First page (limit 10)
        p1 = await ac.get("/notifications?limit=10", headers=auth_headers)
        assert p1.status_code == 200
        data1 = p1.json()
        assert len(data1["items"]) == 10
        assert data1["has_more"] is True
        assert data1["next_cursor"] is not None

        # 3. Second page with cursor
        next_c = data1["next_cursor"]
        p2 = await ac.get(f"/notifications?limit=10&cursor={next_c}", headers=auth_headers)
        assert p2.status_code == 200
        data2 = p2.json()
        assert len(data2["items"]) == 5
        assert data2["has_more"] is False

        # 4. Mark single item as read
        read_single = await ac.post("/notifications/notif-page-0/read", headers=auth_headers)
        assert read_single.status_code == 200

        # Unread count should now be 14
        unread_res2 = await ac.get("/notifications/unread-count", headers=auth_headers)
        assert unread_res2.json()["unread_count"] == 14

        # 5. Mark all as read
        read_all = await ac.post("/notifications/read-all", headers=auth_headers)
        assert read_all.status_code == 200

        unread_res3 = await ac.get("/notifications/unread-count", headers=auth_headers)
        assert unread_res3.json()["unread_count"] == 0

    # Clean up
    await db.notifications_collection.delete_many({"user_id": user_id})
