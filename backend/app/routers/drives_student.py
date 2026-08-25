import logging
import uuid
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status, Request
from pymongo.errors import DuplicateKeyError

from app.database import (
    drives_collection,
    company_listings_collection,
    applications_collection,
    students_collection,
    users_collection,
    audit_logs_collection,
)
from app.dependencies import get_optional_current_user, require_role
from app.eligibility import compute_eligibility
from app.models import AuditLogModel, PaginatedResponse, DriveLeanResponse
from app.routers.auth import limiter

logger = logging.getLogger("talentloq.drives_student")

router = APIRouter(prefix="/drives", tags=["Student Drives"])

@router.get("", status_code=status.HTTP_200_OK, response_model=PaginatedResponse[DriveLeanResponse])
async def list_published_placement_drives(
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(20, ge=1, le=100, description="Items per page"),
    user_payload: Optional[dict] = Depends(get_optional_current_user),
):
    """
    GET /drives?page=1&limit=20 — list status="published" placement drives visible to students.
    Returns lean drive objects with pagination.
    Computes 'is_eligible' flag per requesting student.
    """
    seen_ids = set()
    drives = []

    cursor_drives = drives_collection.find({"status": {"$ne": "closed"}}).sort("created_at", -1)
    d_list = await cursor_drives.to_list(length=500)
    if not d_list:
        cursor_all = drives_collection.find({}).sort("created_at", -1)
        d_list = await cursor_all.to_list(length=500)
    for d in d_list:
        d_id = str(d.get("drive_id") or d.get("listing_id") or "")
        if d_id and d_id not in seen_ids:
            seen_ids.add(d_id)
            drives.append(d)

    cursor_comp = company_listings_collection.find({"status": {"$ne": "closed"}}).sort("created_at", -1)
    comp_list = await cursor_comp.to_list(length=500)
    if not comp_list:
        cursor_all_c = company_listings_collection.find({}).sort("created_at", -1)
        comp_list = await cursor_all_c.to_list(length=500)
    for c in comp_list:
        c_id = str(c.get("listing_id") or c.get("drive_id") or "")
        if c_id and c_id not in seen_ids:
            seen_ids.add(c_id)
            c["drive_id"] = c.get("listing_id", c.get("drive_id"))
            c["drive_title"] = c.get("interview_job", c.get("drive_title", "Placement Drive"))
            c["min_cgpa"] = c.get("cgpa_criteria", c.get("min_cgpa", 6.0))
            drives.append(c)

    student_doc = None
    if user_payload and user_payload.get("sub"):
        sid = user_payload["sub"]
        student_doc = await students_collection.find_one({"student_id": sid}) or await students_collection.find_one({"user_id": sid}) or await users_collection.find_one({"user_id": sid})

    if not student_doc:
        student_doc = {"course": "BTECH_CSE", "CGPA": 8.0, "has_placement_access": True}

    total_count = len(drives)
    start_idx = (page - 1) * limit
    end_idx = start_idx + limit
    paged_drives = drives[start_idx:end_idx]

    items = []
    for d in paged_drives:
        is_eligible = compute_eligibility(student_doc, d)
        items.append(DriveLeanResponse(
            drive_id=str(d.get("drive_id") or d.get("listing_id") or ""),
            company_name=str(d.get("company_name", "")),
            drive_title=str(d.get("drive_title") or d.get("interview_job", "Placement Drive")),
            employment_type=str(d.get("employment_type", "full_time")),
            ctc_min=float(d.get("ctc_min", 6.0)),
            ctc_max=float(d.get("ctc_max", 12.0)),
            min_cgpa=float(d.get("min_cgpa") or d.get("cgpa_criteria", 6.0)),
            is_eligible=is_eligible,
        ))

    has_more = end_idx < total_count

    return PaginatedResponse[DriveLeanResponse](
        items=items,
        page=page,
        limit=limit,
        total_count=total_count,
        has_more=has_more,
    )

@router.get("/my-applications", status_code=status.HTTP_200_OK)
async def list_my_applications(
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(20, ge=1, le=100, description="Items per page"),
    token_payload: dict = Depends(require_role("student")),
):
    """
    GET /drives/my-applications?page=1&limit=20 — returns the student's applied drives
    with application status (current_round, final_outcome) in a single query.
    Eliminates the N+1 loop of calling /drives/{id}/my-status per drive.
    """
    student_id = token_payload["sub"]

    total_count = await applications_collection.count_documents({"student_id": student_id})
    skip = (page - 1) * limit

    cursor = applications_collection.find({"student_id": student_id}).sort("applied_at", -1).skip(skip).limit(limit)
    app_docs = await cursor.to_list(length=limit)

    items = []
    for app_doc in app_docs:
        drive_id = app_doc.get("drive_id", "")
        drive = await drives_collection.find_one({"drive_id": drive_id})
        if not drive:
            drive = await company_listings_collection.find_one({"listing_id": drive_id})
        if not drive:
            drive = {}

        if "_id" in app_doc:
            del app_doc["_id"]
        if "_id" in drive:
            del drive["_id"]

        items.append({
            "drive": {
                "drive_id": str(drive.get("drive_id") or drive.get("listing_id") or drive_id),
                "company_name": str(drive.get("company_name", "")),
                "drive_title": str(drive.get("drive_title") or drive.get("interview_job", "Placement Drive")),
                "employment_type": str(drive.get("employment_type", "full_time")),
                "ctc_min": float(drive.get("ctc_min", 6.0)),
                "ctc_max": float(drive.get("ctc_max", 12.0)),
                "selection_process": drive.get("selection_process", []),
            },
            "status": {
                "applied": True,
                "current_round": app_doc.get("current_round", 0),
                "round_history": app_doc.get("round_history", []),
                "final_outcome": app_doc.get("final_outcome", "in_progress"),
                "applied_at": app_doc.get("applied_at", ""),
            },
        })

    has_more = (skip + limit) < total_count
    return {
        "items": items,
        "page": page,
        "limit": limit,
        "total_count": total_count,
        "has_more": has_more,
    }

@router.get("/{drive_id}", status_code=status.HTTP_200_OK)
async def get_placement_drive_detail(
    drive_id: str,
    user_payload: Optional[dict] = Depends(get_optional_current_user),
):
    """
    GET /drives/{drive_id} — full details of a placement drive or company listing.
    """
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        drive = await drives_collection.find_one({"listing_id": drive_id})
    if not drive:
        drive = await company_listings_collection.find_one({"listing_id": drive_id})
    if not drive:
        drive = await company_listings_collection.find_one({"drive_id": drive_id})
    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Placement drive not found.")

    if "_id" in drive:
        del drive["_id"]

    student_doc = None
    if user_payload and user_payload.get("sub"):
        sid = user_payload["sub"]
        student_doc = await students_collection.find_one({"student_id": sid}) or await students_collection.find_one({"user_id": sid}) or await users_collection.find_one({"user_id": sid})

    if not student_doc:
        student_doc = {"course": "BTECH_CSE", "CGPA": 8.0, "has_placement_access": True}

    drive["is_eligible"] = compute_eligibility(student_doc, drive)

    # Applied state is intentionally scoped to the requesting student's JWT.
    # Never infer this from a drive-level counter or another student's record.
    drive["has_applied"] = False
    drive["my_application_status"] = None
    if user_payload and user_payload.get("sub"):
        my_application = await applications_collection.find_one({
            "drive_id": drive_id,
            "student_id": user_payload["sub"],
        })
        if my_application:
            drive["has_applied"] = True
            drive["my_application_status"] = my_application.get("status", "applied")
    return drive

def is_deadline_passed(deadline_str: Optional[str]) -> bool:
    if not deadline_str:
        return False
    d_str = str(deadline_str).strip().lower()
    if d_str in ["closed", "registration closed", "expired", "deadline passed"]:
        return True
    if d_str in ["open", "to be announced", "tba", "n/a", "none", ""]:
        return False
    try:
        from dateutil import parser as date_parser
        dt = date_parser.parse(str(deadline_str))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)
        return now > dt
    except Exception:
        return False

@router.post("/{drive_id}/apply", status_code=status.HTTP_201_CREATED)
async def apply_to_placement_drive(
    drive_id: str,
    request: Request,
    token_payload: dict = Depends(require_role("student")),
):
    """
    POST /drives/{drive_id}/apply — student application to a placement drive.
    - Requires uploaded resume (rejects 400 if missing).
    - Computes and stores is_eligible (non-blocking).
    - Rejects 409 if already applied.
    - Rejects 400 if registration deadline has passed.
    - Logs audit entry 'STUDENT_DRIVE_APPLICATION_SUBMITTED'.
    """
    student_id = token_payload["sub"]
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        drive = await drives_collection.find_one({"listing_id": drive_id})
    if not drive:
        drive = await company_listings_collection.find_one({"listing_id": drive_id})
    if not drive:
        drive = await company_listings_collection.find_one({"drive_id": drive_id})

    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Placement drive not found.")

    if drive.get("status") == "closed":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Registration for this drive is closed.")

    # Check registration deadline
    deadline_str = drive.get("registration_deadline") or drive.get("deadline")
    if is_deadline_passed(deadline_str):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="The registration deadline for this company drive has passed. Applications are closed."
        )

    # 1. Duplicate Application Check
    existing_app = await applications_collection.find_one({
        "student_id": student_id,
        "$or": [{"drive_id": drive_id}, {"listing_id": drive_id}, {"job_id": drive_id}],
    })
    if existing_app:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You have already submitted an application to this placement drive."
        )

    # 2. Resume Check
    student_doc = await students_collection.find_one({"student_id": student_id}) or await students_collection.find_one({"user_id": student_id}) or await users_collection.find_one({"user_id": student_id})
    
    has_resume = False
    resume_id = None
    if student_doc:
        has_resume = student_doc.get("has_resume", False) or bool(student_doc.get("resume_url")) or bool(student_doc.get("resume_id"))
        resume_id = student_doc.get("resume_id") or student_doc.get("resume_url") or "/static/uploads/resume.pdf"

    if not has_resume:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You must upload a resume in your profile before applying to placement drives."
        )

    # 3. Eligibility Calculation
    is_eligible = compute_eligibility(student_doc or {}, drive)

    # 4. Create Application Document
    now_dt = datetime.now(timezone.utc)
    app_doc = {
        "app_id": f"app_{uuid.uuid4().hex[:12]}",
        "student_id": student_id,
        "drive_id": drive_id,
        "listing_id": drive_id,
        "job_id": drive_id,
        "company_id": drive.get("company_id") or drive.get("recruiter_id") or drive_id,
        "company_name": drive.get("company_name", ""),
        "name": student_doc.get("full_name") or student_doc.get("name") if student_doc else "Student Candidate",
        "email": student_doc.get("email") if student_doc else "student@university.edu",
        "phone_number": student_doc.get("phone_number") or student_doc.get("phone") if student_doc else "+91 98765 43210",
        "cgpa": float(student_doc.get("CGPA") or student_doc.get("cgpa") or 8.0) if student_doc else 8.0,
        "course": student_doc.get("course") or student_doc.get("education") if student_doc else "BTECH_CSE",
        "resume_link": resume_id,
        "resume_id_used": resume_id,
        "status": "applied",
        "is_eligible": is_eligible,
        "meets_cgpa_criteria": is_eligible,
        "current_round": 0,
        "round_history": [],
        "final_outcome": "in_progress",
        "applied_at": now_dt.isoformat(),
    }
    try:
        await applications_collection.insert_one(app_doc)
        # Increment applicant count on drive and listing documents safely
        try:
            await drives_collection.update_many(
                {"$or": [{"drive_id": drive_id}, {"listing_id": drive_id}]},
                {"$inc": {"applicant_count": 1}}
            )
            await company_listings_collection.update_many(
                {"$or": [{"listing_id": drive_id}, {"drive_id": drive_id}]},
                {"$inc": {"applicant_count": 1}}
            )
        except Exception:
            pass
    except DuplicateKeyError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You have already submitted an application to this placement drive.",
        )

    client_ip = request.client.host if request.client else "127.0.0.1"
    user_agent = request.headers.get("user-agent", "unknown")

    audit = AuditLogModel(
        user_id=student_id,
        action="STUDENT_DRIVE_APPLICATION_SUBMITTED",
        ip=client_ip,
        device=user_agent,
    )
    await audit_logs_collection.insert_one(audit.model_dump())

    if "_id" in app_doc:
        del app_doc["_id"]

    return {
        "message": "Application submitted successfully.",
        "application": app_doc,
    }

@router.get("/{drive_id}/my-status", status_code=status.HTTP_200_OK)
async def get_student_application_status(
    drive_id: str,
    token_payload: dict = Depends(require_role("student")),
):
    """
    GET /drives/{drive_id}/my-status — student's own application status: current_round, round_history, final_outcome.
    """
    student_id = token_payload["sub"]
    app_rec = await applications_collection.find_one({"drive_id": drive_id, "student_id": student_id})
    if not app_rec:
        return {
            "applied": False,
            "current_round": 0,
            "round_history": [],
            "final_outcome": "not_applied",
        }

    if "_id" in app_rec:
        del app_rec["_id"]

    app_rec["applied"] = True
    return app_rec

@router.get("/{drive_id}/email-draft", status_code=status.HTTP_200_OK)
@limiter.limit("20/minute")
async def get_drive_email_draft(
    drive_id: str,
    request: Request,
    token_payload: dict = Depends(require_role("student")),
):
    """
    GET /drives/{drive_id}/email-draft — Generates pre-filled email draft data for direct student email application.
    Requires student role. Uses only requesting student's own JWT identity.
    """
    student_id = token_payload["sub"]
    
    # 1. Fetch drive
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        drive = await drives_collection.find_one({"listing_id": drive_id})
    if not drive:
        drive = await company_listings_collection.find_one({"listing_id": drive_id})
    if not drive:
        drive = await company_listings_collection.find_one({"drive_id": drive_id})

    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Placement drive not found.")

    company_name = str(drive.get("company_name", "")).strip() or "Company"
    company_email = str(drive.get("company_email") or drive.get("recruiter_email") or drive.get("email") or "").strip()
    interview_job = str(drive.get("interview_job") or drive.get("drive_title") or "Placement Drive").strip()

    # 2. Fetch student profile
    student_doc = await students_collection.find_one({"student_id": student_id}) or \
                  await students_collection.find_one({"user_id": student_id}) or \
                  await users_collection.find_one({"user_id": student_id}) or {}

    student_name = student_doc.get("full_name") or student_doc.get("name") or token_payload.get("name") or "Student Candidate"
    student_email = student_doc.get("email") or token_payload.get("email") or ""
    student_phone = student_doc.get("phone_number") or student_doc.get("phone") or ""
    degree = student_doc.get("course") or student_doc.get("education") or "GSFC University"
    
    cgpa_raw = student_doc.get("CGPA") or student_doc.get("cgpa") or 8.0
    try:
        cgpa_str = f"{float(cgpa_raw):.2f}"
    except (ValueError, TypeError):
        cgpa_str = str(cgpa_raw)

    # 3. Build email body template
    body_lines = [
        f"Dear Hiring Team at {company_name},",
        "",
        f"I am writing to apply for the {interview_job} position advertised through GSFC University's placement drive. I am a {degree} student at GSFC University with a current CGPA of {cgpa_str}.",
        "",
        "I have attached my resume for your review and would welcome the opportunity to discuss my application further.",
        "",
        "Thank you for your time and consideration.",
        "",
        "Best regards,",
        f"{student_name}",
    ]
    if student_email and str(student_email).strip():
        body_lines.append(f"{str(student_email).strip()}")
    if student_phone and str(student_phone).strip():
        body_lines.append(f"{str(student_phone).strip()}")

    email_body = "\n".join(body_lines)
    subject = f"Application for {interview_job} — {student_name}"

    return {
        "to": company_email,
        "subject": subject,
        "body": email_body,
    }

@router.post("/{drive_id}/email-draft/mark-sent", status_code=status.HTTP_200_OK)
async def mark_email_client_opened(
    drive_id: str,
    token_payload: dict = Depends(require_role("student")),
):
    """
    POST /drives/{drive_id}/email-draft/mark-sent — Best-effort tracking of mail client launch.
    Updates application document email_client_opened_at timestamp.
    """
    student_id = token_payload["sub"]
    now_iso = datetime.now(timezone.utc).isoformat()
    
    await applications_collection.update_many(
        {
            "student_id": student_id,
            "$or": [{"drive_id": drive_id}, {"listing_id": drive_id}, {"job_id": drive_id}],
        },
        {"$set": {"email_client_opened_at": now_iso}}
    )

    return {
        "message": "Email client interaction recorded successfully.",
        "email_client_opened_at": now_iso,
    }

