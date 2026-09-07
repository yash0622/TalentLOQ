import uuid
import logging
from datetime import datetime, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status, HTTPException
from pydantic import BaseModel, Field

from app.database import chat_messages_collection, students_collection
from app.dependencies import get_current_user

logger = logging.getLogger("talentloq.chat")

router = APIRouter(prefix="/chat", tags=["Chat & Messaging"])

class SendMessageRequest(BaseModel):
    recipient_id: str = Field(..., description="Target student_id or recruiter user_id")
    recipient_name: Optional[str] = Field(None, description="Display name of recipient")
    text: str = Field(..., min_length=1, max_length=2000, description="Message text content")
    conversation_id: Optional[str] = Field(None, description="Conversation ID if continuing existing thread")

class ChatMessageResponse(BaseModel):
    message_id: str
    conversation_id: str
    sender_id: str
    sender_name: str
    recipient_id: str
    text: str
    created_at: str
    is_me: bool = True

@router.get("/conversations")
async def list_user_conversations(
    user_payload: dict = Depends(get_current_user),
):
    """
    List all active conversation threads for the authenticated user.
    """
    user_id = user_payload.get("sub", "")
    role = user_payload.get("role", "student")

    # Find distinct conversation IDs involving this user
    pipeline = [
        {
            "$match": {
                "$or": [
                    {"sender_id": user_id},
                    {"recipient_id": user_id},
                ]
            }
        },
        {"$sort": {"created_at": -1}},
        {
            "$group": {
                "_id": "$conversation_id",
                "last_message": {"$first": "$text"},
                "last_message_time": {"$first": "$created_at"},
                "sender_id": {"$first": "$sender_id"},
                "recipient_id": {"$first": "$recipient_id"},
                "sender_name": {"$first": "$sender_name"},
                "recipient_name": {"$first": "$recipient_name"},
                "unread_count": {
                    "$sum": {
                        "$cond": [
                            {"$and": [{"$eq": ["$recipient_id", user_id]}, {"$eq": ["$is_read", False]}]},
                            1,
                            0,
                        ]
                    }
                },
            }
        },
        {"$sort": {"last_message_time": -1}},
    ]

    cursor = chat_messages_collection.aggregate(pipeline)
    conversations = []
    async for doc in cursor:
        conv_id = doc["_id"]
        other_user_id = doc["recipient_id"] if doc["sender_id"] == user_id else doc["sender_id"]
        other_user_name = doc["recipient_name"] if doc["sender_id"] == user_id else doc["sender_name"]
        last_time = doc.get("last_message_time", "")
        time_str = last_time.isoformat() if hasattr(last_time, "isoformat") else str(last_time)

        conversations.append({
            "id": conv_id,
            "name": other_user_name or "Chat",
            "lastMessage": doc.get("last_message", ""),
            "time": time_str,
            "unreadCount": doc.get("unread_count", 0),
            "other_user_id": other_user_id,
        })

    return {"count": len(conversations), "conversations": conversations}

@router.get("/conversations/{conversation_id}/messages")
async def get_conversation_messages(
    conversation_id: str,
    limit: int = Query(50, ge=1, le=200),
    user_payload: dict = Depends(get_current_user),
):
    """
    Fetch message history for a specific conversation thread with authorization check.
    """
    user_id = user_payload.get("sub", "")
    role = user_payload.get("role", "student")

    # Verify participant authorization (admin bypass allowed)
    if role != "admin":
        is_participant = await chat_messages_collection.find_one({
            "conversation_id": conversation_id,
            "$or": [{"sender_id": user_id}, {"recipient_id": user_id}],
        })
        if not is_participant:
            # Check student_id alias if applicable
            student_doc = await students_collection.find_one({
                "$or": [{"user_id": user_id}, {"student_id": user_id}]
            })
            alt_id = student_doc.get("student_id") if student_doc else None
            if alt_id and alt_id != user_id:
                is_participant = await chat_messages_collection.find_one({
                    "conversation_id": conversation_id,
                    "$or": [{"sender_id": alt_id}, {"recipient_id": alt_id}],
                })
            if not is_participant:
                # If thread exists with other users, reject with 403 Forbidden
                any_msg = await chat_messages_collection.find_one({"conversation_id": conversation_id})
                if any_msg:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="Access denied to this conversation thread."
                    )
                return {"conversation_id": conversation_id, "count": 0, "messages": []}

    cursor = chat_messages_collection.find({"conversation_id": conversation_id}).sort("created_at", 1).limit(limit)
    raw_msgs = await cursor.to_list(length=limit)

    messages = []
    for m in raw_msgs:
        created_str = m["created_at"].isoformat() if hasattr(m["created_at"], "isoformat") else str(m["created_at"])
        messages.append({
            "id": m.get("message_id", str(m.get("_id"))),
            "sender_id": m.get("sender_id"),
            "sender_name": m.get("sender_name", "User"),
            "text": m.get("text", ""),
            "time": created_str,
            "is_me": m.get("sender_id") == user_id,
        })

    return {"conversation_id": conversation_id, "count": len(messages), "messages": messages}

@router.post("/messages", status_code=status.HTTP_201_CREATED)
async def send_chat_message(
    data: SendMessageRequest,
    user_payload: dict = Depends(get_current_user),
):
    """
    Send a chat message and persist to database.
    """
    user_id = user_payload.get("sub", "")
    role = user_payload.get("role", "student")

    conv_id = data.conversation_id
    if conv_id and role != "admin":
        # Check if conversation already exists between others
        thread_sample = await chat_messages_collection.find_one({"conversation_id": conv_id})
        if thread_sample:
            is_member = await chat_messages_collection.find_one({
                "conversation_id": conv_id,
                "$or": [{"sender_id": user_id}, {"recipient_id": user_id}],
            })
            if not is_member:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You are not a participant in this conversation thread."
                )

    # Fetch sender profile name
    sender_name = "User"
    if role == "student":
        student_doc = await students_collection.find_one({"user_id": user_id})
        if not student_doc:
            student_doc = await students_collection.find_one({"student_id": user_id})
        if student_doc:
            sender_name = student_doc.get("full_name", "Student")
    else:
        sender_name = "Campus Recruiter"

    conv_id = data.conversation_id
    if not conv_id:
        # Create deterministic conversation ID for pair
        participants = sorted([user_id, data.recipient_id])
        conv_id = f"conv_{participants[0]}_{participants[1]}"

    msg_id = f"msg_{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc)

    msg_doc = {
        "message_id": msg_id,
        "conversation_id": conv_id,
        "sender_id": user_id,
        "sender_name": sender_name,
        "recipient_id": data.recipient_id,
        "recipient_name": data.recipient_name or ("Student" if role == "recruiter" else "Recruiter"),
        "text": data.text,
        "created_at": now,
    }

    await chat_messages_collection.insert_one(msg_doc)

    return {
        "id": msg_id,
        "conversation_id": conv_id,
        "sender_id": user_id,
        "sender_name": sender_name,
        "text": data.text,
        "time": now.isoformat(),
        "is_me": True,
    }