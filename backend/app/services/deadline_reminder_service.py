import asyncio
import logging
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any

from app.database import (
    drives_collection,
    company_listings_collection,
    students_collection,
    applications_collection,
)
from app.eligibility import compute_eligibility
from app.services.push_notification_service import notify

logger = logging.getLogger("talentloq.deadline_reminders")


def _parse_deadline(raw_val: Any) -> datetime | None:
    if not raw_val:
        return None
    if isinstance(raw_val, datetime):
        return raw_val.replace(tzinfo=timezone.utc) if raw_val.tzinfo is None else raw_val
    try:
        # Try ISO format
        dt = datetime.fromisoformat(str(raw_val).replace("Z", "+00:00"))
        return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt
    except Exception:
        pass
    return None


async def check_and_send_deadline_reminders():
    """
    Scans published drives/listings approaching deadline:
    - 24h reminder (23h - 25h remaining)
    - 2h reminder (1h - 3h remaining)
    Targets only eligible students who have not yet applied.
    """
    try:
        now = datetime.now(timezone.utc)
        # Fetch published drives
        cursor = drives_collection.find(
            {"status": {"$in": ["published", "active"]}},
            projection={
                "drive_id": 1,
                "company_name": 1,
                "job_title": 1,
                "application_deadline": 1,
                "deadline": 1,
                "min_cgpa": 1,
                "cgpa_criteria": 1,
                "eligible_courses": 1,
                "max_backlogs": 1,
                "allow_backlogs": 1,
                "placement_policy_flags": 1,
            },
        )
        drives = await cursor.to_list(length=200)

        for drive in drives:
            drive_id = drive.get("drive_id")
            if not drive_id:
                continue

            deadline_dt = _parse_deadline(
                drive.get("application_deadline") or drive.get("deadline")
            )
            if not deadline_dt:
                continue

            time_left = deadline_dt - now
            remind_stage = None
            stage_label = ""

            # Check 24h window (between 23h and 25h)
            if timedelta(hours=23) <= time_left <= timedelta(hours=25):
                remind_stage = "24h"
                stage_label = "24 hours"
            # Check 2h window (between 1h and 3h)
            elif timedelta(hours=1) <= time_left <= timedelta(hours=3):
                remind_stage = "2h"
                stage_label = "2 hours"

            if not remind_stage:
                continue

            company_name = drive.get("company_name", "Placement Drive")
            job_title = drive.get("job_title", "Position")

            # 1. Fetch student IDs who already applied for this drive
            applied_cursor = applications_collection.find(
                {"drive_id": drive_id},
                projection={"student_id": 1, "_id": 0},
            )
            applied_records = await applied_cursor.to_list(length=10000)
            applied_student_ids = {
                rec["student_id"] for rec in applied_records if rec.get("student_id")
            }

            # 2. Fetch candidates with lean projection and check eligibility
            cand_cursor = students_collection.find(
                {},
                projection={
                    "student_id": 1,
                    "user_id": 1,
                    "cgpa": 1,
                    "CGPA": 1,
                    "branch": 1,
                    "course": 1,
                    "degree": 1,
                    "active_backlogs": 1,
                    "placement_policy": 1,
                    "verified_fields": 1,
                },
            )
            all_students = await cand_cursor.to_list(length=5000)

            unapplied_eligible_ids = []
            for st in all_students:
                sid = st.get("student_id") or st.get("user_id")
                if not sid or sid in applied_student_ids:
                    continue

                if compute_eligibility(st, drive):
                    unapplied_eligible_ids.append(sid)

            if not unapplied_eligible_ids:
                continue

            title = f"Deadline Reminder: {company_name}"
            body = f"Only {stage_label} left to apply for {job_title} at {company_name}! Submit your application before the deadline."
            dedup_entity = f"{drive_id}_{remind_stage}"

            await notify(
                user_ids=unapplied_eligible_ids,
                type="deadline_reminder",
                title=title,
                body=body,
                data={
                    "drive_id": drive_id,
                    "entity_id": dedup_entity,
                    "type": "deadline_reminder",
                    "stage": remind_stage,
                },
            )
            logger.info(
                f"[DeadlineReminder] Sent {remind_stage} reminder for drive '{drive_id}' to {len(unapplied_eligible_ids)} student(s)."
            )

    except Exception as e:
        logger.error(f"[DeadlineReminder] Error during reminder scan: {e}", exc_info=True)


async def deadline_reminder_loop(interval_seconds: int = 1800):
    """
    Background loop that wakes up periodically to run deadline checks.
    Runs every 30 minutes by default.
    """
    while True:
        try:
            await check_and_send_deadline_reminders()
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.warning(f"[DeadlineReminder] Loop error: {e}")

        try:
            await asyncio.sleep(interval_seconds)
        except asyncio.CancelledError:
            break
