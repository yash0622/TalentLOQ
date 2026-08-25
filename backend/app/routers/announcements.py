from typing import Dict, Any
from fastapi import APIRouter
from app.database import announcements_collection

router = APIRouter(prefix="/announcements", tags=["Broadcast Announcements"])

@router.get("")
async def get_broadcast_announcements():
    """
    Public student endpoint to view campus placement broadcast announcements.
    """
    cursor = announcements_collection.find({}).sort("created_at", -1)
    announcements = await cursor.to_list(length=50)

    for item in announcements:
        if "_id" in item:
            item["_id"] = str(item["_id"])
        if "created_at" in item and hasattr(item["created_at"], "isoformat"):
            item["created_at"] = item["created_at"].isoformat()

    return {
        "count": len(announcements),
        "announcements": announcements,
    }
