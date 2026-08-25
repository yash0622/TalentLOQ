from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Depends, Query, status
from app.database import audit_logs_collection, async_db
from app.dependencies import require_role, require_recent_reauth

router = APIRouter(prefix="/admin", tags=["Admin & Security Monitoring"])
agent_runs_collection = async_db["agent_runs"]

@router.get("/audit-logs")
async def get_audit_logs(
    limit: int = Query(50, ge=1, le=200),
    skip: int = Query(0, ge=0),
    action: Optional[str] = Query(None, description="Filter by action string"),
    user_id: Optional[str] = Query(None, description="Filter by user_id"),
    token_payload: dict = Depends(require_role("recruiter")),
    reauth_payload: dict = Depends(require_recent_reauth(max_age_seconds=300)),
):
    """
    Admin-only endpoint for reviewing recent audit_logs entries.
    Protected by require_role('recruiter') and require_recent_reauth(300s).
    """
    query: Dict[str, Any] = {}
    if action:
        query["action"] = {"$regex": action, "$options": "i"}
    if user_id:
        query["user_id"] = user_id

    cursor = audit_logs_collection.find(query).sort("timestamp", -1).skip(skip).limit(limit)
    logs = await cursor.to_list(length=limit)

    # Format datetime for JSON response
    for item in logs:
        item["_id"] = str(item["_id"])
        if "timestamp" in item and hasattr(item["timestamp"], "isoformat"):
            item["timestamp"] = item["timestamp"].isoformat()

    return {
        "count": len(logs),
        "logs": logs,
    }

@router.get("/agent-runs")
async def get_agent_runs(
    limit: int = Query(50, ge=1, le=200),
    skip: int = Query(0, ge=0),
    token_payload: dict = Depends(require_role("recruiter")),
    reauth_payload: dict = Depends(require_recent_reauth(max_age_seconds=300)),
):
    """
    Admin-only endpoint for reviewing AI Agent decision logs.
    """
    cursor = agent_runs_collection.find({}).sort("timestamp", -1).skip(skip).limit(limit)
    runs = await cursor.to_list(length=limit)

    for item in runs:
        item["_id"] = str(item["_id"])
        if "timestamp" in item and hasattr(item["timestamp"], "isoformat"):
            item["timestamp"] = item["timestamp"].isoformat()

    return {
        "count": len(runs),
        "runs": runs,
    }
