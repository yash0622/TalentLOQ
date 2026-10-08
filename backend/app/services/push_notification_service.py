import asyncio
import logging
import uuid
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional

from fastapi import BackgroundTasks
from app.database import (
    notifications_collection,
    device_tokens_collection,
    notification_preferences_collection,
)
from app.firebase_manager import send_multicast_fcm

logger = logging.getLogger("talentloq.push_service")

# Map notification type to preference category
TYPE_TO_PREFERENCE_CATEGORY = {
    "drive_published": "drive_alerts",
    "company_published": "drive_alerts",
    "deadline_reminder": "drive_alerts",
    "round_outcome": "round_results",
    "applicant_shortlisted": "round_results",
    "applicant_rejected": "round_results",
    "round_progressed": "round_results",
    "offer": "offers",
    "offer_recorded": "offers",
    "chat_message": "chat_messages",
    "new_message": "chat_messages",
}

DEFAULT_PREFERENCES = {
    "drive_alerts": True,
    "round_results": True,
    "offers": True,
    "chat_messages": True,
}


async def _deduplicate_users(
    user_ids: List[str],
    notif_type: str,
    data: Optional[Dict[str, Any]],
) -> List[str]:
    """
    Deduplicates: (same user + type + entity_id) must not be notified twice.
    """
    if not user_ids or not data:
        return user_ids

    entity_id = (
        data.get("entity_id")
        or data.get("drive_id")
        or data.get("listing_id")
        or data.get("document_id")
        or data.get("message_id")
    )
    if not entity_id or not str(entity_id).strip():
        return user_ids

    entity_str = str(entity_id).strip()
    non_duplicate_users = []

    # Check for existing notifications for these users with same type & entity_id
    for uid in user_ids:
        exists = await notifications_collection.find_one(
            {
                "user_id": uid,
                "type": notif_type,
                "$or": [
                    {"data.entity_id": entity_str},
                    {"data.drive_id": entity_str},
                    {"data.listing_id": entity_str},
                    {"data.document_id": entity_str},
                    {"data.message_id": entity_str},
                ],
            },
            projection={"_id": 1},
        )
        if not exists:
            non_duplicate_users.append(uid)
        else:
            logger.debug(f"[PushService] Dedup skipped: user '{uid}' already received '{notif_type}' for entity '{entity_str}'")

    return non_duplicate_users


async def _filter_users_by_preference(
    user_ids: List[str],
    notif_type: str,
) -> List[str]:
    """
    Filters out users who turned off notifications for this category.
    """
    category = TYPE_TO_PREFERENCE_CATEGORY.get(notif_type)
    if not category or not user_ids:
        return user_ids

    # Query preferences only for users who have explicitly set them
    cursor = notification_preferences_collection.find(
        {"user_id": {"$in": user_ids}},
        projection={"user_id": 1, category: 1},
    )
    opted_out_users = set()
    async for pref in cursor:
        if pref.get(category) is False:
            opted_out_users.add(pref.get("user_id"))

    if opted_out_users:
        logger.info(f"[PushService] Filtered {len(opted_out_users)} user(s) who opted out of category '{category}'")

    return [uid for uid in user_ids if uid not in opted_out_users]


async def _dispatch_push_worker(
    target_users: List[str],
    title: str,
    body: str,
    data: Optional[Dict[str, Any]],
) -> None:
    """
    Internal worker: fetches device tokens, batches in 500, sends FCM multicast,
    and prunes invalid tokens. Wrapped in try/except so it never breaks caller.
    """
    try:
        if not target_users:
            return

        # Query only user_id and token fields with projection
        cursor = device_tokens_collection.find(
            {"user_id": {"$in": target_users}},
            projection={"user_id": 1, "token": 1, "_id": 0},
        )
        tokens_records = await cursor.to_list(length=10000)
        tokens = [rec["token"] for rec in tokens_records if rec.get("token")]

        if not tokens:
            logger.debug(f"[PushService] No registered device tokens for {len(target_users)} target user(s).")
            return

        # Prepare clean string payload for FCM
        payload_data = {str(k): str(v) for k, v in (data or {}).items() if v is not None}

        # Send in batches of 500 per FCM limits
        batch_size = 500
        for i in range(0, len(tokens), batch_size):
            batch = tokens[i : i + batch_size]
            success_count, dead_tokens = send_multicast_fcm(
                tokens=batch,
                title=title,
                body=body,
                data=payload_data,
            )

            # Prune invalid/unregistered tokens
            if dead_tokens:
                del_res = await device_tokens_collection.delete_many({"token": {"$in": dead_tokens}})
                logger.info(f"[PushService] Pruned {del_res.deleted_count} dead/unregistered token(s) from database.")

    except Exception as e:
        logger.error(f"[PushService] Error in push notification worker: {e}", exc_info=True)


async def notify(
    user_ids: List[str],
    type: str,
    title: str,
    body: str,
    data: Optional[Dict[str, Any]] = None,
    background_tasks: Optional[BackgroundTasks] = None,
) -> Dict[str, Any]:
    """
    High-level notification service:
    1. Deduplicates (same user + type + entity_id).
    2. Saves in-app inbox record for every user.
    3. Respects user category preferences.
    4. Dispatches FCM multicast in batches of 500 (non-blocking).
    5. Cleans up invalid tokens.
    """
    if not user_ids:
        return {"status": "skipped", "reason": "No recipient user_ids", "count": 0}

    # Ensure data has type and entity_id for deep linking
    data_dict = dict(data or {})
    if "type" not in data_dict:
        data_dict["type"] = type
    if "entity_id" not in data_dict:
        for possible_key in ["drive_id", "listing_id", "document_id", "conversation_id", "message_id"]:
            if possible_key in data_dict:
                data_dict["entity_id"] = data_dict[possible_key]
                break

    # 1. Deduplication
    eligible_users = await _deduplicate_users(user_ids, type, data_dict)
    if not eligible_users:
        return {"status": "deduplicated", "reason": "All recipients already notified", "count": 0}

    now = datetime.now(timezone.utc)

    # 2. Save inbox records for each eligible user
    inbox_docs = []
    for uid in eligible_users:
        inbox_docs.append(
            {
                "notification_id": f"notif_{uuid.uuid4().hex[:12]}",
                "user_id": uid,
                "type": type,
                "title": title,
                "body": body,
                "data": data_dict,
                "read": False,
                "created_at": now,
            }
        )

    try:
        if inbox_docs:
            await notifications_collection.insert_many(inbox_docs)
    except Exception as e:
        logger.warning(f"[PushService] Failed to insert inbox records: {e}")

    # 3. Filter users based on category preferences for the push alert
    push_eligible_users = await _filter_users_by_preference(eligible_users, type)

    # 4. Non-blocking push dispatch
    if background_tasks is not None:
        background_tasks.add_task(
            _dispatch_push_worker,
            push_eligible_users,
            title,
            body,
            data_dict,
        )
    else:
        # Launch asyncio background task so main action is never blocked
        asyncio.create_task(
            _dispatch_push_worker(
                push_eligible_users,
                title,
                body,
                data_dict,
            )
        )

    return {
        "status": "success",
        "inbox_saved_count": len(eligible_users),
        "push_targeted_count": len(push_eligible_users),
    }
