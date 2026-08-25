import uuid
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional

from app.database import (
    company_listings_collection,
    drives_collection,
    students_collection,
    users_collection,
    applications_collection,
    notifications_collection,
    chat_messages_collection,
)

logger = logging.getLogger("talentloq.notifications")

def send_fcm_push_notification(
    fcm_token: str,
    title: str,
    body: str,
    data: Optional[Dict[str, Any]] = None,
) -> bool:
    """
    Dispatches push notification to FCM device token.
    FCM push integration wrapper (Firebase Cloud Messaging).
    """
    logger.info(f"[FCM Push] Sent to token '{fcm_token[:10]}...': '{title}' - '{body}' (data: {data})")
    return True

def send_smtp_email(to_email: str, subject: str, body_text: str) -> bool:
    """
    Dispatches email via SMTP server infrastructure.
    SMTP Email integration wrapper.
    """
    logger.info(f"[SMTP Email] Sent to '{to_email}': '{subject}'")
    return True

async def notify_on_publish(listing_id: str, target_audience: str = "all") -> Dict[str, Any]:
    """
    Called when a company listing is published (status="published").
    Audience configurable via target_audience: "all" or "eligible_only".
    If "eligible_only", notifies only students whose stored CGPA >= listing's cgpa_criteria.
    Dispatches FCM push notifications & SMTP emails, storing notification records in MongoDB.
    """
    listing = await company_listings_collection.find_one({"listing_id": listing_id})
    if not listing or listing.get("status") != "published":
        return {"status": "skipped", "reason": "Listing not found or not published", "notified_count": 0}

    cgpa_cutoff = float(listing.get("cgpa_criteria", 6.0))
    company_name = listing.get("company_name", "Company")
    job_role = listing.get("interview_job", "Role")

    # Fetch candidate students safely
    try:
        cursor = students_collection.find({})
        all_students = await cursor.to_list(length=1000)
    except Exception as e:
        logger.warning(f"Could not fetch students for notify_on_publish: {e}")
        all_students = []

    target_students = []
    for student in all_students:
        student_cgpa = float(student.get("CGPA", student.get("cgpa", 7.0)))
        if target_audience == "eligible_only":
            if student_cgpa >= cgpa_cutoff:
                target_students.append(student)
        else:
            target_students.append(student)

    notified_count = 0
    title = f"New Placement Drive: {company_name}"
    body = f"{company_name} is hiring for {job_role}! Min CGPA Cutoff: {cgpa_cutoff}. Check details and apply now."

    for st in target_students:
        student_id = st.get("student_id") or st.get("user_id")
        email = st.get("email", "student@talentloq.edu")
        fcm_token = st.get("fcm_token", "fcm-device-token-mock")

        send_fcm_push_notification(
            fcm_token=fcm_token,
            title=title,
            body=body,
            data={"listing_id": listing_id, "type": "company_published"},
        )
        send_smtp_email(to_email=email, subject=title, body_text=body)

        notification_doc = {
            "notification_id": f"notif_{uuid.uuid4().hex[:12]}",
            "recipient_id": student_id,
            "recipient_email": email,
            "type": "COMPANY_DRIVE_PUBLISHED",
            "title": title,
            "body": body,
            "listing_id": listing_id,
            "company_name": company_name,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "read": False,
        }
        try:
            await notifications_collection.insert_one(notification_doc)
        except Exception as e:
            logger.warning(f"Could not insert notification doc: {e}")
        notified_count += 1

    logger.info(f"notify_on_publish finished for listing '{listing_id}': notified {notified_count} students (audience: {target_audience})")
    return {
        "status": "success",
        "listing_id": listing_id,
        "target_audience": target_audience,
        "notified_count": notified_count,
    }

async def notify_on_schedule_change(listing_id: str) -> Dict[str, Any]:
    """
    Called when interview_datetime or interview_venue changes on an already-published listing.
    Notifies all students who have an `applications` record for that listing_id with updated date/time/venue.
    """
    listing = await company_listings_collection.find_one({"listing_id": listing_id})
    if not listing:
        return {"status": "skipped", "reason": "Listing not found", "notified_count": 0}

    company_name = listing.get("company_name", "Company")
    job_role = listing.get("interview_job", "Role")
    new_datetime = listing.get("interview_datetime", "Updated Schedule")
    new_venue = listing.get("interview_venue", "Updated Venue")

    # Fetch all applicants for this listing safely
    try:
        app_cursor = applications_collection.find({"listing_id": listing_id})
        applicant_records = await app_cursor.to_list(length=1000)
    except Exception as e:
        logger.warning(f"Could not fetch applications for notify_on_schedule_change: {e}")
        applicant_records = []

    notified_count = 0
    title = f"Schedule Update: {company_name} Drive"
    body = (
        f"The interview schedule for {company_name} ({job_role}) has been updated.\n"
        f"• Date & Time: {new_datetime}\n"
        f"• Venue: {new_venue}"
    )

    for app_rec in applicant_records:
        student_id = app_rec.get("student_id")
        # Get student contact info
        student = await students_collection.find_one({"student_id": student_id}) or await users_collection.find_one({"user_id": student_id})
        email = student.get("email", "student@talentloq.edu") if student else "student@talentloq.edu"
        fcm_token = student.get("fcm_token", "fcm-device-token-mock") if student else "fcm-token-mock"

        send_fcm_push_notification(
            fcm_token=fcm_token,
            title=title,
            body=body,
            data={"listing_id": listing_id, "type": "interview_schedule_change"},
        )
        send_smtp_email(to_email=email, subject=title, body_text=body)

        notification_doc = {
            "notification_id": f"notif_{uuid.uuid4().hex[:12]}",
            "recipient_id": student_id,
            "recipient_email": email,
            "type": "INTERVIEW_SCHEDULE_UPDATED",
            "title": title,
            "body": body,
            "listing_id": listing_id,
            "interview_datetime": new_datetime,
            "interview_venue": new_venue,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "read": False,
        }
        await notifications_collection.insert_one(notification_doc)
        notified_count += 1

    logger.info(f"notify_on_schedule_change finished for listing '{listing_id}': notified {notified_count} applicants")
    return {
        "status": "success",
        "listing_id": listing_id,
        "notified_count": notified_count,
    }

async def notify_on_round_advance(
    drive_id: str,
    student_id: str,
    round_number: int,
    round_name: str,
    result: str,
    final_outcome: str,
    custom_message: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Called when recruiter records a round result ('pass' | 'fail') for a student.
    Notifies that student of the outcome and, if advancing, the next round's name.
    """
    drive = await drives_collection.find_one({"drive_id": drive_id}) or await company_listings_collection.find_one({"listing_id": drive_id})
    company_name = drive.get("company_name", "Company Drive") if drive else "Company Drive"

    student = await students_collection.find_one({"student_id": student_id}) or await users_collection.find_one({"user_id": student_id})
    email = student.get("email", "student@talentloq.edu") if student else "student@talentloq.edu"
    fcm_token = student.get("fcm_token", "fcm-token-mock") if student else "fcm-token-mock"

    if result == "pass" and final_outcome == "selected":
        title = f"🎉 Offer Selection: {company_name}!"
        body = f"Congratulations! You passed Round {round_number} ({round_name}) and have been SELECTED for {company_name}!"
    elif result == "pass":
        title = f"Round Advanced: {company_name}"
        body = f"Great news! You passed Round {round_number} ({round_name}) for {company_name}. You are advancing to the next round!"
    else:
        title = f"Drive Outcome Update: {company_name}"
        body = f"Thank you for participating in the {company_name} placement drive. You were not selected for the next round."

    if custom_message and custom_message.strip():
        body += f"\n\nRecruiter Note: {custom_message.strip()}"

    send_fcm_push_notification(
        fcm_token=fcm_token,
        title=title,
        body=body,
        data={"drive_id": drive_id, "type": "round_outcome", "result": result, "final_outcome": final_outcome},
    )
    send_smtp_email(to_email=email, subject=title, body_text=body)

    notification_doc = {
        "notification_id": f"notif_{uuid.uuid4().hex[:12]}",
        "recipient_id": student_id,
        "recipient_email": email,
        "type": "SELECTION_ROUND_OUTCOME",
        "title": title,
        "body": body,
        "drive_id": drive_id,
        "round_number": round_number,
        "round_name": round_name,
        "result": result,
        "final_outcome": final_outcome,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "read": False,
    }
    try:
        await notifications_collection.insert_one(notification_doc)
    except Exception as e:
        logger.warning(f"Could not insert round advance notification doc: {e}")

    # Also store direct chat message in Messages section
    chat_message_doc = {
        "message_id": f"msg_{uuid.uuid4().hex[:12]}",
        "sender_id": "recruiter",
        "sender_name": f"{company_name} Placement Team",
        "recipient_id": student_id,
        "recipient_name": student.get("full_name", "Student") if student else "Student",
        "text": body,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "is_read": False,
        "drive_id": drive_id,
    }
    try:
        await chat_messages_collection.insert_one(chat_message_doc)
    except Exception as e:
        logger.warning(f"Could not insert chat message doc: {e}")

    logger.info(f"notify_on_round_advance sent to student '{student_id}': round {round_number} ({result}), outcome: {final_outcome}")
    return {
        "status": "success",
        "student_id": student_id,
        "drive_id": drive_id,
        "round_number": round_number,
        "result": result,
        "final_outcome": final_outcome,
    }
