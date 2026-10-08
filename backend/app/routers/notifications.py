import logging
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
from bson import ObjectId
from fastapi import APIRouter, Depends, Query, status, HTTPException, BackgroundTasks
from pydantic import BaseModel, Field

from app.database import (
    device_tokens_collection,
    notifications_collection,
    notification_preferences_collection,
)
from app.dependencies import get_current_user
from app.services.push_notification_service import (
    notify,
    DEFAULT_PREFERENCES,
)

logger = logging.getLogger("talentloq.notifications_router")

router = APIRouter(prefix="/notifications", tags=["Notifications & FCM Push"])


# --- Request / Response Models ---

class DeviceTokenRequest(BaseModel):
    token: str = Field(..., min_length=1, description="Firebase Cloud Messaging device token")
    platform: Optional[str] = Field("android", description="Device platform (android/ios/web)")
    app_version: Optional[str] = Field("1.0.0", description="Installed app version")


class NotificationPreferencesModel(BaseModel):
    drive_alerts: bool = True
    round_results: bool = True
    offers: bool = True
    chat_messages: bool = True


class TestPushRequest(BaseModel):
    target_user_id: Optional[str] = Field(None, description="Optional user ID; defaults to current caller")
    title: str = Field("TalentLOQ Test Push", description="Notification title")
    body: str = Field("This is a live test notification from TalentLOQ.", description="Notification body")
    data: Optional[Dict[str, Any]] = Field(default_factory=dict, description="Custom payload for deep linking")


# --- Endpoints ---

@router.post("/device-token", status_code=status.HTTP_200_OK)
async def register_device_token(
    payload: DeviceTokenRequest,
    user_payload: dict = Depends(get_current_user),
):
    """
    POST /notifications/device-token
    Register or refresh FCM device token.
    If the token exists for another user (device transferred or re-logged in),
    it is automatically reassigned to the currently authenticated user.
    """
    token_str = payload.token.strip()
    if not token_str:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Device token cannot be empty")

    user_id = user_payload.get("sub", "")
    now = datetime.now(timezone.utc)

    # Upsert with reassign on unique token
    await device_tokens_collection.update_one(
        {"token": token_str},
        {
            "$set": {
                "user_id": user_id,
                "platform": (payload.platform or "android").lower(),
                "app_version": payload.app_version or "1.0.0",
                "last_seen": now,
            },
            "$setOnInsert": {
                "created_at": now,
            },
        },
        upsert=True,
    )

    logger.info(f"[DeviceToken] Registered token for user '{user_id}' on platform '{payload.platform}'")
    return {"status": "ok", "message": "Device token registered successfully."}


@router.delete("/device-token", status_code=status.HTTP_200_OK)
async def delete_device_token(
    token: Optional[str] = Query(None, description="Specific token to unregister; if omitted, clears all for user"),
    user_payload: dict = Depends(get_current_user),
):
    """
    DELETE /notifications/device-token
    Called on user logout to revoke push delivery to this device.
    """
    user_id = user_payload.get("sub", "")
    query: Dict[str, Any] = {"user_id": user_id}
    if token and token.strip():
        query["token"] = token.strip()

    result = await device_tokens_collection.delete_many(query)
    logger.info(f"[DeviceToken] Deleted {result.deleted_count} token(s) for user '{user_id}'")
    return {"status": "ok", "deleted_count": result.deleted_count}


@router.get("", status_code=status.HTTP_200_OK)
async def get_user_notifications(
    cursor: Optional[str] = Query(None, description="Cursor for pagination (ISO datetime of last received item)"),
    limit: int = Query(20, ge=1, le=100, description="Items per page"),
    user_payload: dict = Depends(get_current_user),
):
    """
    GET /notifications?cursor=&limit=20
    Cursor-paginated in-app notification inbox. Light fields only.
    """
    user_id = user_payload.get("sub", "")
    query: Dict[str, Any] = {"user_id": user_id}

    if cursor:
        try:
            # Parse cursor as ISO timestamp
            cursor_dt = datetime.fromisoformat(cursor.replace("Z", "+00:00"))
            query["created_at"] = {"$lt": cursor_dt}
        except Exception:
            pass

    # Lean projection: only necessary fields
    projection = {
        "_id": 1,
        "notification_id": 1,
        "user_id": 1,
        "type": 1,
        "title": 1,
        "body": 1,
        "data": 1,
        "read": 1,
        "created_at": 1,
    }

    cursor_res = (
        notifications_collection.find(query, projection)
        .sort("created_at", -1)
        .limit(limit + 1)
    )
    docs = await cursor_res.to_list(length=limit + 1)

    has_more = len(docs) > limit
    items_to_return = docs[:limit]

    formatted_items = []
    for d in items_to_return:
        created = d.get("created_at")
        created_str = created.isoformat() if hasattr(created, "isoformat") else str(created)
        formatted_items.append(
            {
                "id": d.get("notification_id") or str(d.get("_id")),
                "type": d.get("type", "GENERAL"),
                "title": d.get("title", ""),
                "body": d.get("body", ""),
                "data": d.get("data") or {},
                "read": bool(d.get("read", False)),
                "created_at": created_str,
            }
        )

    next_cursor = None
    if has_more and items_to_return:
        last_item = items_to_return[-1]
        last_created = last_item.get("created_at")
        next_cursor = last_created.isoformat() if hasattr(last_created, "isoformat") else str(last_created)

    return {
        "items": formatted_items,
        "next_cursor": next_cursor,
        "has_more": has_more,
    }


@router.get("/unread-count", status_code=status.HTTP_200_OK)
async def get_unread_notification_count(
    user_payload: dict = Depends(get_current_user),
):
    """
    GET /notifications/unread-count
    Returns unread badge count for the app bar bell icon.
    """
    user_id = user_payload.get("sub", "")
    count = await notifications_collection.count_documents(
        {"user_id": user_id, "read": False}
    )
    return {"unread_count": count}


@router.post("/{notification_id}/read", status_code=status.HTTP_200_OK)
async def mark_notification_read(
    notification_id: str,
    user_payload: dict = Depends(get_current_user),
):
    """
    POST /notifications/{notification_id}/read
    Marks a specific notification as read.
    """
    user_id = user_payload.get("sub", "")
    query: Dict[str, Any] = {
        "user_id": user_id,
        "$or": [
            {"notification_id": notification_id},
            {"_id": ObjectId(notification_id) if ObjectId.is_valid(notification_id) else None},
        ],
    }

    res = await notifications_collection.update_one(query, {"$set": {"read": True}})
    if res.matched_count == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found")

    return {"status": "ok", "message": "Notification marked as read."}


@router.post("/read-all", status_code=status.HTTP_200_OK)
async def mark_all_notifications_read(
    user_payload: dict = Depends(get_current_user),
):
    """
    POST /notifications/read-all
    Marks all notifications for the authenticated user as read.
    """
    user_id = user_payload.get("sub", "")
    res = await notifications_collection.update_many(
        {"user_id": user_id, "read": False},
        {"$set": {"read": True}},
    )
    return {"status": "ok", "marked_read_count": res.modified_count}


@router.get("/preferences", status_code=status.HTTP_200_OK)
async def get_notification_preferences(
    user_payload: dict = Depends(get_current_user),
):
    """
    GET /notifications/preferences
    Retrieves user notification delivery preferences.
    """
    user_id = user_payload.get("sub", "")
    pref = await notification_preferences_collection.find_one(
        {"user_id": user_id},
        projection={"_id": 0, "user_id": 0},
    )
    if not pref:
        return DEFAULT_PREFERENCES

    return {
        "drive_alerts": pref.get("drive_alerts", True),
        "round_results": pref.get("round_results", True),
        "offers": pref.get("offers", True),
        "chat_messages": pref.get("chat_messages", True),
    }


@router.put("/preferences", status_code=status.HTTP_200_OK)
async def update_notification_preferences(
    payload: NotificationPreferencesModel,
    user_payload: dict = Depends(get_current_user),
):
    """
    PUT /notifications/preferences
    Updates user notification preferences (drive alerts, round results, offers, chat).
    """
    user_id = user_payload.get("sub", "")
    now = datetime.now(timezone.utc)

    await notification_preferences_collection.update_one(
        {"user_id": user_id},
        {
            "$set": {
                "drive_alerts": payload.drive_alerts,
                "round_results": payload.round_results,
                "offers": payload.offers,
                "chat_messages": payload.chat_messages,
                "updated_at": now,
            }
        },
        upsert=True,
    )

    return {"status": "ok", "preferences": payload.model_dump()}


@router.post("/test-push", status_code=status.HTTP_200_OK)
async def send_test_push(
    payload: TestPushRequest,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_current_user),
):
    """
    POST /notifications/test-push (Debug endpoint)
    Dispatches a live push notification to the given user_id (or caller by default).
    """
    caller_id = user_payload.get("sub", "")
    target_id = payload.target_user_id or caller_id

    result = await notify(
        user_ids=[target_id],
        type="test_push",
        title=payload.title,
        body=payload.body,
        data=payload.data or {"type": "test_push", "entity_id": "test_123"},
        background_tasks=background_tasks,
    )

    return {"status": "ok", "result": result}
