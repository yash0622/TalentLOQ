import logging
import uuid
from datetime import datetime, timezone
from typing import Dict, Any, Optional
from app.database import audit_logs_collection, async_db

logger = logging.getLogger("talentloq.audit")

agent_runs_collection = async_db["agent_runs"]

async def log_audit_event(
    user_id: str,
    action: str,
    ip: str = "127.0.0.1",
    device: str = "unknown",
    details: Optional[Dict[str, Any]] = None,
) -> str:
    """
    Centralized audit logging for all security & authentication events.
    Writes to MongoDB 'audit_logs' collection.
    """
    log_id = str(uuid.uuid4())
    doc = {
        "log_id": log_id,
        "user_id": user_id,
        "action": action,
        "ip": ip,
        "device": device,
        "details": details or {},
        "timestamp": datetime.now(timezone.utc),
    }
    await audit_logs_collection.insert_one(doc)
    logger.info(f"[AUDIT] user={user_id} action={action} ip={ip} device={device}")
    return log_id

async def log_agent_decision(
    user_id: str,
    agent_type: str,
    action: str,
    proposal_details: Dict[str, Any],
    approved: bool = False,
    ip: str = "127.0.0.1",
) -> str:
    """
    Logs AI agent decisions (Auto-Apply proposals, resume matching, automated scheduling)
    into 'agent_runs' collection and cross-links to unified 'audit_logs' for security review.
    """
    run_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc)

    agent_doc = {
        "agent_run_id": run_id,
        "user_id": user_id,
        "agent_type": agent_type,
        "action": action,
        "proposal_details": proposal_details,
        "approved": approved,
        "timestamp": timestamp,
    }
    await agent_runs_collection.insert_one(agent_doc)

    # Cross-reference in main audit logs
    await log_audit_event(
        user_id=user_id,
        action=f"AI_AGENT_{action.upper()}",
        ip=ip,
        device="AI_AGENT",
        details={"agent_run_id": run_id, "approved": approved},
    )
    return run_id
