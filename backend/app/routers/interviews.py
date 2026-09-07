import uuid
import logging
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.database import interviews_collection, students_collection, users_collection, notifications_collection
from app.dependencies import get_current_user, require_role

logger = logging.getLogger("talentloq.interviews")

router = APIRouter(prefix="/interviews", tags=["Interview Scheduling"])

class InterviewBookingRequest(BaseModel):
    student_id: str
    candidate_name: Optional[str] = None
    drive_id: Optional[str] = None
    date: str = Field(..., description="e.g. Thu, Jul 24")
    time_slot: str = Field(..., description="e.g. 10:00 AM - 10:45 AM")
    interview_type: str = Field(..., description="e.g. Technical System Design")
    meeting_link: Optional[str] = "https://meet.google.com/talentloq-interview"
    location: Optional[str] = "GSFC University Campus Placement Hall / Online"

@router.post("/schedule", status_code=status.HTTP_201_CREATED)
async def schedule_candidate_interview(
    data: InterviewBookingRequest,
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    Recruiter schedules an interview slot with a candidate.
    Persists to MongoDB and dispatches a student notification.
    """
    recruiter_id = token_payload.get("sub", "")
    interview_id = f"intv_{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc)

    # Student lookup
    candidate_name = data.candidate_name
    student_user_id = data.student_id
    student_email = None
    st = await students_collection.find_one({"$or": [{"student_id": data.student_id}, {"user_id": data.student_id}]})
    if st:
        if not candidate_name:
            candidate_name = st.get("full_name", "Candidate")
        student_user_id = st.get("user_id", data.student_id)
        student_email = st.get("email")

    doc = {
        "interview_id": interview_id,
        "student_id": data.student_id,
        "candidate_name": candidate_name or "Candidate",
        "recruiter_id": recruiter_id,
        "drive_id": data.drive_id,
        "date": data.date,
        "time": data.time_slot,
        "interview_type": data.interview_type,
        "meeting_link": data.meeting_link,
        "location": data.location,
        "status": "scheduled",
        "outcome": "pending",
        "created_at": now,
    }

    await interviews_collection.insert_one(doc)

    # Push notification to student with canonical recipient_id and recipient_email
    notif_doc = {
        "notification_id": f"notif_{uuid.uuid4().hex[:12]}",
        "recipient_id": student_user_id,
        "recipient_email": student_email,
        "user_id": student_user_id,
        "student_id": data.student_id,
        "title": "Interview Scheduled!",
        "message": f"Your {data.interview_type} interview is scheduled on {data.date} at {data.time_slot}.",
        "type": "interview_scheduled",
        "is_read": False,
        "created_at": now,
    }
    await notifications_collection.insert_one(notif_doc)

    return {
        "message": f"Interview scheduled successfully with {candidate_name}.",
        "interview_id": interview_id,
        "interview": {
            "id": interview_id,
            "candidate_name": candidate_name,
            "date": data.date,
            "time": data.time_slot,
            "interview_type": data.interview_type,
            "status": "scheduled",
        }
    }

@router.get("/my-interviews")
async def get_my_interviews(
    user_payload: dict = Depends(get_current_user),
):
    """
    Fetch all scheduled interviews for current user (student or recruiter).
    """
    user_id = user_payload.get("sub", "")
    role = user_payload.get("role", "student")

    query = {"student_id": user_id} if role == "student" else {"recruiter_id": user_id}
    cursor = interviews_collection.find(query).sort("created_at", -1)
    interviews = await cursor.to_list(length=100)

    for item in interviews:
        item["_id"] = str(item["_id"])
        if "created_at" in item and hasattr(item["created_at"], "isoformat"):
            item["created_at"] = item["created_at"].isoformat()

    return {"count": len(interviews), "interviews": interviews}
