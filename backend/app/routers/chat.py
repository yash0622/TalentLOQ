import uuid
import re
import json
import logging
from datetime import datetime, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.database import chat_messages_collection, students_collection
from app.dependencies import get_current_user
from app.security import sanitize_text

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
        is_recruiter_bot = str(conv_id).endswith("_recruiter_ai_bot") or conv_id == "recruiter_ai_bot"
        is_bot_thread = is_recruiter_bot or str(conv_id).endswith("_ai_bot") or conv_id == "ai_bot"
        
        if is_recruiter_bot:
            other_user_id = "recruiter_ai_bot"
            display_name = "Talent Scout"
            conv_id_clean = "recruiter_ai_bot"
        elif is_bot_thread:
            other_user_id = "ai_bot"
            display_name = "Placement Assistant"
            conv_id_clean = "ai_bot"
        else:
            other_user_id = doc["recipient_id"] if doc["sender_id"] == user_id else doc["sender_id"]
            display_name = (doc["recipient_name"] if doc["sender_id"] == user_id else doc["sender_name"]) or "Chat"
            conv_id_clean = conv_id

        last_time = doc.get("last_message_time", "")
        time_str = last_time.isoformat() if hasattr(last_time, "isoformat") else str(last_time)
        last_text = doc.get("last_message", "")
        unread = doc.get("unread_count", 0)

        conversations.append({
            "id": conv_id_clean,
            "name": display_name,
            "candidate_name": display_name,
            "last_message": last_text,
            "lastMessage": last_text,
            "time": time_str,
            "last_message_time": time_str,
            "unread_count": unread,
            "unreadCount": unread,
            "other_user_id": other_user_id,
        })

    # Deduplicate bot conversations — keep only one entry per cleaned ID
    seen_ids = {}
    deduped = []
    for c in conversations:
        cid = c["id"]
        if cid in seen_ids:
            # Keep the one with higher unread count or more recent time
            existing = seen_ids[cid]
            existing["unread_count"] = existing.get("unread_count", 0) + c.get("unread_count", 0)
            existing["unreadCount"] = existing["unread_count"]
            continue
        seen_ids[cid] = c
        deduped.append(c)
    conversations = deduped

    # Ensure Recruiter AI Bot is available for recruiters
    if role == "recruiter":
        has_recruiter_bot = any(c["id"] in ["recruiter_ai_bot"] for c in conversations)
        if not has_recruiter_bot:
            conversations.insert(0, {
                "id": "recruiter_ai_bot",
                "name": "TalentLOQ Assistant",
                "candidate_name": "TalentLOQ Assistant",
                "last_message": "Ask me anything about candidates.",
                "lastMessage": "Ask me anything about candidates.",
                "time": "Always Active",
                "last_message_time": "Always Active",
                "unread_count": 0,
                "unreadCount": 0,
                "other_user_id": "recruiter_ai_bot",
            })

    return {"count": len(conversations), "conversations": conversations}

@router.get("/ai-agent/criteria")
async def get_agent_criteria(
    user_payload: dict = Depends(get_current_user),
):
    """
    Get active parsed AI placement agent criteria for the authenticated student.
    """
    user_id = user_payload.get("sub", "")
    student = await students_collection.find_one({
        "$or": [{"user_id": user_id}, {"student_id": user_id}]
    })
    prefs = (student.get("career_preferences") if student else {}) or {}
    raw_auto = prefs.get("auto_apply_enabled")
    if raw_auto is None:
        raw_auto = prefs.get("autonomous_apply_enabled", False)
    auto_enabled = bool(raw_auto)
    last_inst = prefs.get("raw_instruction") or prefs.get("last_instruction") or ""

    return {
        "target_roles": prefs.get("target_roles", []),
        "preferred_domains": prefs.get("preferred_domains", []),
        "min_ctc_lpa": prefs.get("min_ctc_lpa"),
        "max_ctc_lpa": prefs.get("max_ctc_lpa"),
        "autonomous_apply_enabled": auto_enabled,
        "last_instruction": last_inst,
        "updated_at": prefs.get("updated_at", ""),
    }

@router.get("/ai/sessions")
async def get_ai_chat_sessions(
    user_payload: dict = Depends(get_current_user),
):
    """
    Get previous AI chat sessions for the authenticated user.
    """
    user_id = user_payload.get("sub", "")
    role = user_payload.get("role", "student")
    bot_type = "recruiter_ai_bot" if role == "recruiter" else "ai_bot"
    prefix = f"conv_{user_id}_{bot_type}"

    query = {
        "$or": [
            {"conversation_id": prefix},
            {"conversation_id": {"$regex": f"^{re.escape(prefix)}"}},
            {"conversation_id": bot_type, "$or": [{"sender_id": user_id}, {"recipient_id": user_id}]},
        ]
    }

    cursor = chat_messages_collection.find(query).sort("created_at", 1)
    all_msgs = await cursor.to_list(length=1000)

    groups = {}
    for m in all_msgs:
        cid = m.get("conversation_id", prefix)
        if cid not in groups:
            groups[cid] = []
        groups[cid].append(m)

    sessions = []
    for cid, msgs in groups.items():
        if not msgs:
            continue
        first_user_msg = next((m for m in msgs if m.get("sender_id") == user_id), msgs[0])
        title = first_user_msg.get("text", "New Conversation").strip()
        title = title.split("\n")[0][:45]
        if not title:
            title = "Conversation"

        last_msg = msgs[-1]
        last_time = last_msg.get("created_at")
        time_str = last_time.isoformat() if hasattr(last_time, "isoformat") else str(last_time)

        if cid == prefix or cid == bot_type:
            ext_id = bot_type
        elif cid.startswith(f"{prefix}_"):
            ext_id = f"{bot_type}_{cid[len(prefix) + 1:]}"
        else:
            ext_id = cid

        sessions.append({
            "id": ext_id,
            "title": title,
            "last_message": last_msg.get("text", ""),
            "time": time_str,
            "message_count": len(msgs),
        })

    sessions.sort(key=lambda s: s["time"], reverse=True)
    return {"sessions": sessions}

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

    is_recruiter_bot = (
        conversation_id in ["recruiter_ai_bot", "recruiter-ai-bot"]
        or conversation_id.startswith("recruiter_ai_bot_")
        or conversation_id.endswith("_recruiter_ai_bot")
        or (role == "recruiter" and (conversation_id in ["ai_bot", "ai-bot"] or conversation_id.startswith("ai_bot_")))
    )
    is_ai_bot = is_recruiter_bot or (
        conversation_id in ["ai_bot", "ai-bot"]
        or conversation_id.startswith("ai_bot_")
        or conversation_id.endswith("_ai_bot")
    )

    if is_recruiter_bot:
        if conversation_id.startswith("recruiter_ai_bot_"):
            sess = conversation_id[len("recruiter_ai_bot_"):]
            target_conv_id = f"conv_{user_id}_recruiter_ai_bot_{sess}"
            query = {"conversation_id": target_conv_id}
        else:
            target_conv_id = f"conv_{user_id}_recruiter_ai_bot"
            query = {
                "$or": [
                    {"conversation_id": target_conv_id},
                    {"conversation_id": "recruiter_ai_bot", "sender_id": user_id},
                    {"conversation_id": "recruiter_ai_bot", "recipient_id": user_id},
                    {"conversation_id": "ai_bot", "sender_id": user_id, "recipient_id": "recruiter_ai_bot"},
                ]
            }
    elif is_ai_bot:
        if conversation_id.startswith("ai_bot_"):
            sess = conversation_id[len("ai_bot_"):]
            target_conv_id = f"conv_{user_id}_ai_bot_{sess}"
            query = {"conversation_id": target_conv_id}
        else:
            target_conv_id = f"conv_{user_id}_ai_bot"
            query = {
                "$or": [
                    {"conversation_id": target_conv_id},
                    {"conversation_id": "ai_bot", "sender_id": user_id},
                    {"conversation_id": "ai_bot", "recipient_id": user_id},
                ]
            }
    else:
        target_conv_id = conversation_id
        # Verify participant authorization (admin bypass allowed)
        if role != "admin":
            is_participant = await chat_messages_collection.find_one({
                "conversation_id": target_conv_id,
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
                        "conversation_id": target_conv_id,
                        "$or": [{"sender_id": alt_id}, {"recipient_id": alt_id}],
                    })
                if not is_participant:
                    # If thread exists with other users, reject with 403 Forbidden
                    any_msg = await chat_messages_collection.find_one({"conversation_id": target_conv_id})
                    if any_msg:
                        raise HTTPException(
                            status_code=status.HTTP_403_FORBIDDEN,
                            detail="Access denied to this conversation thread."
                        )
                    return {"conversation_id": target_conv_id, "count": 0, "messages": []}

        query = {"conversation_id": target_conv_id}

    cursor = chat_messages_collection.find(query).sort("created_at", -1).limit(limit)
    raw_msgs = await cursor.to_list(length=limit)
    raw_msgs.reverse()

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

    return {"conversation_id": target_conv_id, "count": len(messages), "messages": messages}


@router.delete("/conversations/{conversation_id}")
async def delete_conversation_messages(
    conversation_id: str,
    user_payload: dict = Depends(get_current_user),
):
    """
    DELETE /chat/conversations/{conversation_id} — delete all chat messages in a conversation.
    """
    user_id = user_payload.get("sub", "")
    role = user_payload.get("role", "student")

    is_recruiter_bot = (
        conversation_id in ["recruiter_ai_bot", "recruiter-ai-bot"]
        or conversation_id.startswith("recruiter_ai_bot_")
        or conversation_id.endswith("_recruiter_ai_bot")
        or (role == "recruiter" and (conversation_id in ["ai_bot", "ai-bot"] or conversation_id.startswith("ai_bot_")))
    )
    is_ai_bot = is_recruiter_bot or (
        conversation_id in ["ai_bot", "ai-bot"]
        or conversation_id.startswith("ai_bot_")
        or conversation_id.endswith("_ai_bot")
    )

    if is_recruiter_bot:
        if conversation_id.startswith("recruiter_ai_bot_"):
            sess = conversation_id[len("recruiter_ai_bot_"):]
            target_conv_id = f"conv_{user_id}_recruiter_ai_bot_{sess}"
            query = {
                "$or": [
                    {"conversation_id": target_conv_id},
                    {"conversation_id": conversation_id},
                    {"conversation_id": {"$regex": f"{re.escape(sess)}$"}},
                ]
            }
        else:
            target_conv_id = f"conv_{user_id}_recruiter_ai_bot"
            query = {
                "$or": [
                    {"conversation_id": target_conv_id},
                    {"conversation_id": {"$regex": f"^conv_{re.escape(user_id)}_recruiter_ai_bot"}},
                    {"conversation_id": "recruiter_ai_bot", "sender_id": user_id},
                    {"conversation_id": "recruiter_ai_bot", "recipient_id": user_id},
                    {"conversation_id": "ai_bot", "sender_id": user_id, "recipient_id": "recruiter_ai_bot"},
                    {"conversation_id": {"$regex": r"^recruiter_ai_bot_"}},
                ]
            }
    elif is_ai_bot:
        if conversation_id.startswith("ai_bot_"):
            sess = conversation_id[len("ai_bot_"):]
            target_conv_id = f"conv_{user_id}_ai_bot_{sess}"
            query = {
                "$or": [
                    {"conversation_id": target_conv_id},
                    {"conversation_id": conversation_id},
                    {"conversation_id": {"$regex": f"{re.escape(sess)}$"}},
                ]
            }
        else:
            target_conv_id = f"conv_{user_id}_ai_bot"
            query = {
                "$or": [
                    {"conversation_id": target_conv_id},
                    {"conversation_id": {"$regex": f"^conv_{re.escape(user_id)}_ai_bot"}},
                    {"conversation_id": "ai_bot", "sender_id": user_id},
                    {"conversation_id": "ai_bot", "recipient_id": user_id},
                    {"conversation_id": {"$regex": r"^ai_bot_"}},
                ]
            }
    else:
        query = {
            "conversation_id": conversation_id,
            "$or": [{"sender_id": user_id}, {"recipient_id": user_id}],
        }

    res = await chat_messages_collection.delete_many(query)
    return {"status": "ok", "deleted_count": res.deleted_count}


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

    # 1. Normalize conversation ID & Detect Bot
    is_recruiter_bot = (
        data.recipient_id in ["recruiter_ai_bot", "recruiter-ai-bot"]
        or data.conversation_id in ["recruiter_ai_bot", "recruiter-ai-bot"]
        or (role == "recruiter" and (data.recipient_id in ["ai_bot", "ai-bot"] or data.conversation_id in ["ai_bot", "ai-bot"]))
        or (data.conversation_id and data.conversation_id.endswith("_recruiter_ai_bot"))
    )
    is_student_bot = (
        not is_recruiter_bot and (
            data.recipient_id == "ai_bot"
            or data.conversation_id == "ai_bot"
            or (data.conversation_id and data.conversation_id.endswith("_ai_bot"))
        )
    )
    is_bot = is_recruiter_bot or is_student_bot

    if is_recruiter_bot:
        if data.conversation_id and data.conversation_id.startswith("recruiter_ai_bot_"):
            sess = data.conversation_id[len("recruiter_ai_bot_"):]
            conv_id = f"conv_{user_id}_recruiter_ai_bot_{sess}"
        else:
            conv_id = f"conv_{user_id}_recruiter_ai_bot"
    elif is_student_bot:
        if data.conversation_id and data.conversation_id.startswith("ai_bot_"):
            sess = data.conversation_id[len("ai_bot_"):]
            conv_id = f"conv_{user_id}_ai_bot_{sess}"
        else:
            conv_id = f"conv_{user_id}_ai_bot"
    elif data.conversation_id:
        conv_id = data.conversation_id
    else:
        participants = sorted([user_id, data.recipient_id])
        conv_id = f"conv_{participants[0]}_{participants[1]}"

    # 2. Check participant access only for non-bot conversations
    if not is_bot and role != "admin" and data.conversation_id:
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

    clean_text = sanitize_text(data.text)
    if not clean_text:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Message content cannot be empty after sanitization."
        )

    msg_id = f"msg_{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc)

    msg_doc = {
        "message_id": msg_id,
        "conversation_id": conv_id,
        "sender_id": user_id,
        "sender_name": sender_name,
        "recipient_id": "recruiter_ai_bot" if is_recruiter_bot else data.recipient_id,
        "recipient_name": ("AI Talent Scout" if is_recruiter_bot else (data.recipient_name or ("Student" if role == "recruiter" else "Recruiter"))),
        "text": clean_text,
        "created_at": now,
    }

    await chat_messages_collection.insert_one(msg_doc)

    bot_msg_data = None
    if is_recruiter_bot:
        from app.services.llm_logger import reset_llm_counter
        reset_llm_counter()
        from app.services.recruiter_ai_agent import recruiter_hybrid_agent
        bot_res = await recruiter_hybrid_agent.process_recruiter_message(user_id, clean_text, conv_id)
        if isinstance(bot_res, dict):
            bot_msg_data = {
                "id": bot_res.get("id"),
                "conversation_id": bot_res.get("conversation_id", conv_id),
                "sender_id": bot_res.get("sender_id", "recruiter_ai_bot"),
                "sender_name": bot_res.get("sender_name", "AI Talent Scout"),
                "text": bot_res.get("text", ""),
                "time": bot_res.get("time", datetime.now(timezone.utc).isoformat()),
                "is_me": False,
            }
    elif is_student_bot:
        from app.services.llm_logger import reset_llm_counter
        reset_llm_counter()
        from app.services.ai_bot_assistant import ai_bot_assistant
        reply_text = await ai_bot_assistant.process_student_message(user_id, clean_text, conv_id)
        bot_msg_data = {
            "id": f"msg_{uuid.uuid4().hex[:12]}",
            "conversation_id": conv_id,
            "sender_id": "ai_bot",
            "sender_name": "AI Bot",
            "text": reply_text or "",
            "time": datetime.now(timezone.utc).isoformat(),
            "is_me": False,
        }

    return {
        "id": msg_id,
        "conversation_id": conv_id,
        "sender_id": user_id,
        "sender_name": sender_name,
        "text": clean_text,
        "time": now.isoformat(),
        "is_me": True,
        "bot_response": bot_msg_data,
    }


@router.post("/messages/stream")
async def send_chat_message_stream(
    data: SendMessageRequest,
    user_payload: dict = Depends(get_current_user),
):
    """
    Real-time Server-Sent Events (SSE) streaming endpoint for AI chatbot interactions.
    Yields data: {"chunk": token}\n\n and final data: {"done": true, ...}\n\n.
    """
    user_id = user_payload.get("sub", "")
    role = user_payload.get("role", "student")

    is_recruiter_bot = (
        data.recipient_id in ["recruiter_ai_bot", "recruiter-ai-bot"]
        or data.conversation_id in ["recruiter_ai_bot", "recruiter-ai-bot"]
        or (role == "recruiter" and (data.recipient_id in ["ai_bot", "ai-bot"] or data.conversation_id in ["ai_bot", "ai-bot"]))
        or (data.conversation_id and data.conversation_id.endswith("_recruiter_ai_bot"))
    )
    is_student_bot = (
        not is_recruiter_bot and (
            data.recipient_id == "ai_bot"
            or data.conversation_id == "ai_bot"
            or (data.conversation_id and data.conversation_id.endswith("_ai_bot"))
        )
    )
    is_bot = is_recruiter_bot or is_student_bot

    if is_recruiter_bot:
        if data.conversation_id and data.conversation_id.startswith("recruiter_ai_bot_"):
            sess = data.conversation_id[len("recruiter_ai_bot_"):]
            conv_id = f"conv_{user_id}_recruiter_ai_bot_{sess}"
        else:
            conv_id = f"conv_{user_id}_recruiter_ai_bot"
    elif is_student_bot:
        if data.conversation_id and data.conversation_id.startswith("ai_bot_"):
            sess = data.conversation_id[len("ai_bot_"):]
            conv_id = f"conv_{user_id}_ai_bot_{sess}"
        else:
            conv_id = f"conv_{user_id}_ai_bot"
    elif data.conversation_id:
        conv_id = data.conversation_id
    else:
        participants = sorted([user_id, data.recipient_id])
        conv_id = f"conv_{participants[0]}_{participants[1]}"

    if not is_bot and role != "admin" and data.conversation_id:
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

    sender_name = "User"
    if role == "student":
        student_doc = await students_collection.find_one({"user_id": user_id})
        if not student_doc:
            student_doc = await students_collection.find_one({"student_id": user_id})
        if student_doc:
            sender_name = student_doc.get("full_name", "Student")
    else:
        sender_name = "Campus Recruiter"

    clean_text = sanitize_text(data.text)
    if not clean_text:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Message content cannot be empty after sanitization."
        )

    msg_id = f"msg_{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc)

    msg_doc = {
        "message_id": msg_id,
        "conversation_id": conv_id,
        "sender_id": user_id,
        "sender_name": sender_name,
        "recipient_id": "recruiter_ai_bot" if is_recruiter_bot else data.recipient_id,
        "recipient_name": ("AI Talent Scout" if is_recruiter_bot else (data.recipient_name or ("Student" if role == "recruiter" else "Recruiter"))),
        "text": clean_text,
        "created_at": now,
    }
    await chat_messages_collection.insert_one(msg_doc)

    async def sse_generator():
        # Ponytail: standard SSE event stream yielding JSON chunks
        if is_recruiter_bot:
            from app.services.llm_logger import reset_llm_counter
            reset_llm_counter()
            from app.services.recruiter_ai_agent import recruiter_hybrid_agent
            async for event in recruiter_hybrid_agent.stream_recruiter_message(user_id, clean_text, conv_id):
                yield f"data: {json.dumps(event)}\n\n"
        elif is_student_bot:
            from app.services.llm_logger import reset_llm_counter
            reset_llm_counter()
            from app.services.ai_bot_assistant import ai_bot_assistant
            reply_text = await ai_bot_assistant.process_student_message(user_id, clean_text, conv_id)
            bot_id = f"msg_{uuid.uuid4().hex[:12]}"
            yield f"data: {json.dumps({'chunk': reply_text})}\n\n"
            yield f"data: {json.dumps({'done': True, 'id': bot_id, 'text': reply_text})}\n\n"
        else:
            yield f"data: {json.dumps({'done': True, 'id': msg_id, 'text': clean_text})}\n\n"

    return StreamingResponse(sse_generator(), media_type="text/event-stream")