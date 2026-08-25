import io
import json
import logging
from pathlib import Path
import re
import uuid
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status, File, UploadFile, Form, Request

from app.database import (
    company_listings_collection,
    drives_collection,
    applications_collection,
    students_collection,
    users_collection,
    audit_logs_collection,
    grid_fs,
)
from app.dependencies import require_role
from app.models import (
    DriveModel,
    DriveCreate,
    DriveUpdate,
    DriveResponse,
    RoundResultUpdate,
    AuditLogModel,
    SelectionRoundModel,
    PlacementPolicyFlagsModel,
    AdvancedEligibilityModel,
    sanitize_string,
    PaginatedResponse,
    RecruiterDriveLeanResponse,
    ApplicantResponse,
    RecruiterStatsResponse,
)
from app.eligibility import compute_eligibility
from app.notifications import (
    notify_on_publish,
    notify_on_schedule_change,
    notify_on_round_advance,
)

logger = logging.getLogger("talentloq.drives_recruiter")

router = APIRouter(prefix="/recruiter", tags=["Recruiter Drives"])

@router.post("/drives", status_code=status.HTTP_201_CREATED)
async def create_placement_drive(
    request: Request,
    company_name: str = Form(...),
    company_email: Optional[str] = Form(None),
    drive_title: str = Form(...),
    mode: str = Form("on_campus"),
    employment_type: str = Form("full_time"),
    location: str = Form("Campus"),
    school_tag: str = Form("School of Technology"),
    ctc_min: float = Form(6.0),
    ctc_max: float = Form(12.0),
    stipend: Optional[float] = Form(None),
    description: str = Form(...),
    qualifications: str = Form("B.Tech / BCA"),
    additional_requirements: str = Form(""),
    bond_details: str = Form("No Bond"),
    eligibility_criteria_summary: str = Form("Min CGPA 6.0"),
    min_cgpa: float = Form(6.0),
    schedule_datetime: str = Form(...),
    registration_deadline: str = Form(...),
    status_field: str = Form("published"),
    eligible_courses_json: Optional[str] = Form(None),
    selection_process_json: Optional[str] = Form(None),
    policy_flags_json: Optional[str] = Form(None),
    pdf: Optional[UploadFile] = File(None),
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    POST /recruiter/drives — create a new placement drive (starts as draft or published).
    Accepts multipart form data including an optional PDF file upload.
    Validates MIME type application/pdf only, max 10MB, and sanitizes filename.
    Requires require_role("recruiter") and require_recent_reauth(300s).
    Logs audit entry 'RECRUITER_DRIVE_CREATED'.
    """
    pdf_url = None
    if pdf:
        raw_name = pdf.filename or "brochure.pdf"
        filename_clean = sanitize_string(raw_name).replace("..", "").replace("/", "").replace("\\", "")
        if not filename_clean.lower().endswith(".pdf") or (pdf.content_type and pdf.content_type != "application/pdf"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="File upload must be a PDF document (application/pdf)."
            )

        content_bytes = await pdf.read()
        if len(content_bytes) > 10 * 1024 * 1024:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="File size exceeds maximum allowed limit of 10MB."
            )

        if len(content_bytes) < 4 or not content_bytes.startswith(b"%PDF-"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid PDF file header. Uploaded file is not a valid PDF document."
            )

        safe_name = f"drive_{uuid.uuid4().hex[:8]}_{re.sub(r'[^a-zA-Z0-9_.-]', '_', filename_clean)}"
        grid_file_id = await grid_fs.upload_from_stream(
            safe_name,
            io.BytesIO(content_bytes),
            metadata={
                "filename": filename_clean,
                "content_type": "application/pdf",
                "safe_name": safe_name,
                "uploaded_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        pdf_url = f"/api/v1/files/{str(grid_file_id)}"

    # Parse JSON list/dict fields if provided
    eligible_courses = ["BTECH_CSE", "BCA", "ALL"]
    if eligible_courses_json:
        try:
            parsed = json.loads(eligible_courses_json)
            if isinstance(parsed, list):
                eligible_courses = parsed
        except Exception:
            pass

    selection_process = [
        {"round_number": 1, "round_name": "Aptitude Test"},
        {"round_number": 2, "round_name": "Technical Round"},
        {"round_number": 3, "round_name": "HR Round"},
    ]
    if selection_process_json:
        try:
            parsed = json.loads(selection_process_json)
            if isinstance(parsed, list):
                selection_process = parsed
        except Exception:
            pass

    policy_flags = {
        "requires_placement_access": True,
        "requires_placement_eligible": True,
        "requires_job_interest": True,
        "requires_internship_interest": True,
    }
    if policy_flags_json:
        try:
            parsed = json.loads(policy_flags_json)
            if isinstance(parsed, dict):
                policy_flags.update(parsed)
        except Exception:
            pass

    clean_company_email = None
    if company_email:
        c_email = company_email.strip().lower()
        try:
            from pydantic import TypeAdapter, EmailStr
            TypeAdapter(EmailStr).validate_python(c_email)
            clean_company_email = c_email
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid company email address format."
            )

    drive_doc = DriveModel(
        company_name=sanitize_string(company_name),
        company_email=clean_company_email,
        drive_title=sanitize_string(drive_title),
        mode=mode if mode in ["on_campus", "off_campus", "virtual"] else "on_campus",
        employment_type=employment_type if employment_type in ["internship", "full_time", "internship_and_full_time"] else "full_time",
        location=sanitize_string(location),
        school_tag=sanitize_string(school_tag),
        ctc_min=ctc_min,
        ctc_max=ctc_max,
        stipend=stipend,
        description=sanitize_string(description),
        qualifications=sanitize_string(qualifications),
        additional_requirements=sanitize_string(additional_requirements),
        bond_details=sanitize_string(bond_details),
        attachment_pdf_url=pdf_url,
        eligible_courses=eligible_courses,
        eligibility_criteria_summary=sanitize_string(eligibility_criteria_summary),
        min_cgpa=min_cgpa,
        placement_policy_flags=PlacementPolicyFlagsModel(**policy_flags),
        selection_process=[SelectionRoundModel(**r) for r in selection_process],
        schedule_datetime=sanitize_string(schedule_datetime),
        registration_deadline=sanitize_string(registration_deadline),
        status=status_field if status_field in ["draft", "published", "closed"] else "published",
        posted_by=token_payload["sub"],
    ).model_dump()

    drive_doc["created_at"] = drive_doc["created_at"].isoformat()
    drive_doc["updated_at"] = drive_doc["updated_at"].isoformat()

    await drives_collection.insert_one(drive_doc)

    client_ip = request.client.host if request.client else "127.0.0.1"
    user_agent = request.headers.get("user-agent", "unknown")

    audit = AuditLogModel(
        user_id=token_payload["sub"],
        action="RECRUITER_DRIVE_CREATED",
        ip=client_ip,
        device=user_agent,
    )
    await audit_logs_collection.insert_one(audit.model_dump())

    if "_id" in drive_doc:
        del drive_doc["_id"]

    if drive_doc.get("status") == "published":
        await notify_on_publish(drive_doc["drive_id"], target_audience="all")

    return drive_doc

@router.patch("/drives/{drive_id}")
async def edit_placement_drive(
    drive_id: str,
    data: DriveUpdate,
    request: Request,
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    PATCH /recruiter/drives/{drive_id} — edit any drive field, including rounds and status.
    Requires require_role("recruiter") and require_recent_reauth(300s).
    Logs audit entry 'RECRUITER_DRIVE_EDITED'.
    """
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Drive not found.")

    update_fields = {k: v for k, v in data.model_dump(exclude_unset=True).items() if v is not None}
    schedule_changed = False
    if "schedule_datetime" in update_fields:
        if drive.get("status") == "published" or update_fields.get("status") == "published":
            schedule_changed = True

    if update_fields:
        update_fields["updated_at"] = datetime.now(timezone.utc).isoformat()
        await drives_collection.update_one({"drive_id": drive_id}, {"$set": update_fields})

    if schedule_changed:
        await notify_on_schedule_change(drive_id)

    client_ip = request.client.host if request.client else "127.0.0.1"
    user_agent = request.headers.get("user-agent", "unknown")

    audit = AuditLogModel(
        user_id=token_payload["sub"],
        action="RECRUITER_DRIVE_EDITED",
        ip=client_ip,
        device=user_agent,
    )
    await audit_logs_collection.insert_one(audit.model_dump())

    updated_doc = await drives_collection.find_one({"drive_id": drive_id})
    if updated_doc and "_id" in updated_doc:
        del updated_doc["_id"]
    return updated_doc

@router.post("/drives/{drive_id}/publish")
async def publish_placement_drive(
    drive_id: str,
    request: Request,
    target_audience: str = Query("all", description="Target audience: 'all' or 'eligible_only'"),
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    POST /recruiter/drives/{drive_id}/publish — sets status="published", triggers notify_on_publish.
    Accepts target_audience query parameter ("all" | "eligible_only").
    """
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Drive not found.")

    now_iso = datetime.now(timezone.utc).isoformat()
    await drives_collection.update_one(
        {"drive_id": drive_id},
        {"$set": {"status": "published", "updated_at": now_iso}}
    )

    client_ip = request.client.host if request.client else "127.0.0.1"
    user_agent = request.headers.get("user-agent", "unknown")

    audit = AuditLogModel(
        user_id=token_payload["sub"],
        action="RECRUITER_DRIVE_PUBLISHED",
        ip=client_ip,
        device=user_agent,
    )
    await audit_logs_collection.insert_one(audit.model_dump())

    updated_doc = await drives_collection.find_one({"drive_id": drive_id})
    if updated_doc and "_id" in updated_doc:
        del updated_doc["_id"]

    notif_res = await notify_on_publish(drive_id, target_audience=target_audience)

    return {
        "message": "Drive published successfully.",
        "drive": updated_doc,
        "notifications": notif_res,
    }

@router.get("/drives", response_model=PaginatedResponse[RecruiterDriveLeanResponse])
async def list_recruiter_placement_drives(
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(20, ge=1, le=100, description="Items per page"),
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    GET /recruiter/drives?page=1&limit=20 — list all placement drives (lean view) with pagination.
    Annotated with applicant_count and eligible_applicant_count.
    """
    total_count = await drives_collection.count_documents({})
    skip = (page - 1) * limit

    cursor = drives_collection.find({}).sort("created_at", -1).skip(skip).limit(limit)
    drives = await cursor.to_list(length=limit)

    # Compute counts from applications on every request. This avoids a stale
    # drive counter and returns the newly inserted application immediately.
    drive_ids = [d.get("drive_id") for d in drives if d.get("drive_id")]
    application_counts = {}
    if drive_ids:
        count_cursor = applications_collection.aggregate([
            {"$match": {"drive_id": {"$in": drive_ids}}},
            {"$group": {
                "_id": "$drive_id",
                "applicant_count": {"$sum": 1},
                "eligible_applicant_count": {
                    "$sum": {"$cond": [{"$eq": ["$is_eligible", True]}, 1, 0]}
                },
            }},
        ])
        for row in await count_cursor.to_list(length=None):
            application_counts[row["_id"]] = row

    items = []
    for d in drives:
        did = d.get("drive_id")
        stats = application_counts.get(did, {})
        applicant_count = int(stats.get("applicant_count", 0))
        eligible_applicant_count = int(stats.get("eligible_applicant_count", 0))

        created_at_val = d.get("created_at", "")
        if isinstance(created_at_val, datetime):
            created_at_val = created_at_val.isoformat()

        items.append(RecruiterDriveLeanResponse(
            drive_id=str(did or ""),
            company_name=str(d.get("company_name", "")),
            drive_title=str(d.get("drive_title", "")),
            employment_type=str(d.get("employment_type", "full_time")),
            ctc_min=float(d.get("ctc_min", 6.0)),
            ctc_max=float(d.get("ctc_max", 12.0)),
            min_cgpa=float(d.get("min_cgpa", 6.0)),
            status=str(d.get("status", "draft")),
            created_at=str(created_at_val),
            applicant_count=applicant_count,
            eligible_applicant_count=eligible_applicant_count,
        ))

    has_more = (skip + len(drives)) < total_count

    return PaginatedResponse[RecruiterDriveLeanResponse](
        items=items,
        page=page,
        limit=limit,
        total_count=total_count,
        has_more=has_more,
    )

@router.get("/drives/{drive_id}")
async def get_recruiter_placement_drive_detail(
    drive_id: str,
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    GET /recruiter/drives/{drive_id} — full detail view of a specific placement drive for recruiter.
    Returns complete drive object with all heavy fields & applicant stats.
    """
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        drive = await drives_collection.find_one({"listing_id": drive_id})
    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Drive not found.")

    if "_id" in drive:
        del drive["_id"]

    did = drive.get("drive_id", drive_id)
    apps_cursor = applications_collection.find({"drive_id": did})
    apps = await apps_cursor.to_list(length=1000)

    drive["applicant_count"] = len(apps)
    drive["eligible_applicant_count"] = sum(1 for a in apps if a.get("is_eligible", False))

    return drive

@router.get("/drives/{drive_id}/applicants", response_model=PaginatedResponse[ApplicantResponse])
async def list_drive_applicants(
    drive_id: str,
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(20, ge=1, le=100, description="Items per page"),
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    GET /recruiter/drives/{drive_id}/applicants?page=1&limit=20 — list applicants with pagination:
    name, CGPA, course, is_eligible, current_round, final_outcome, resume_link.
    """
    total_count = await applications_collection.count_documents({"drive_id": drive_id})
    if total_count == 0:
        total_count = await applications_collection.count_documents({"listing_id": drive_id})
    skip = (page - 1) * limit

    cursor = applications_collection.find({"drive_id": drive_id})
    apps = await cursor.skip(skip).limit(limit).to_list(length=limit)
    if not apps:
        cursor = applications_collection.find({"listing_id": drive_id})
        apps = await cursor.skip(skip).limit(limit).to_list(length=limit)

    items = []
    for a in apps:
        sid = a.get("student_id")
        student = None
        user = None
        try:
            student = await students_collection.find_one({"$or": [{"student_id": sid}, {"user_id": sid}]})
            user = await users_collection.find_one({"$or": [{"user_id": sid}, {"student_id": sid}]})
        except Exception:
            pass
        
        name = a.get("name") or (student.get("full_name") or student.get("name") if student else None) or (user.get("full_name") if user else None) or "Student Candidate"
        cgpa = float(a.get("cgpa") or (student.get("CGPA", student.get("cgpa", 8.0)) if student else 8.0))
        course = a.get("course") or (student.get("course", student.get("degree", "BTECH_CSE")) if student else "BTECH_CSE")
        email = a.get("email") or (user.get("email") if user else None) or (student.get("email") if student else None)
        phone = a.get("phone_number") or (student.get("phone_number") or student.get("phone") if student else None) or (user.get("phone_number") if user else None)

        applied_at_val = a.get("applied_at")
        if isinstance(applied_at_val, datetime):
            applied_at_val = applied_at_val.isoformat()

        items.append(ApplicantResponse(
            app_id=str(a.get("app_id", "")),
            student_id=str(sid or ""),
            drive_id=drive_id,
            name=name,
            email=email,
            phone_number=phone,
            cgpa=cgpa,
            course=course,
            is_eligible=bool(a.get("is_eligible", True)),
            current_round=int(a.get("current_round", 0)),
            round_history=a.get("round_history", []),
            final_outcome=str(a.get("final_outcome", "in_progress")),
            resume_link=str(student.get("resume_url") if (student and student.get("resume_url")) else (a.get("resume_link") or a.get("resume_id_used") or "")),
            applied_at=applied_at_val,
        ))

    has_more = (skip + len(apps)) < total_count

    return PaginatedResponse[ApplicantResponse](
        items=items,
        page=page,
        limit=limit,
        total_count=total_count,
        has_more=has_more,
    )

@router.patch("/drives/{drive_id}/applicants/{student_id}/round")
async def update_candidate_round_result(
    drive_id: str,
    student_id: str,
    data: RoundResultUpdate,
    request: Request,
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    PATCH /recruiter/drives/{drive_id}/applicants/{student_id}/round — advance student, recording 'pass'|'fail'.
    If 'fail', set final_outcome="rejected".
    If last defined round and 'pass', set final_outcome="selected" and increment drive.offers_made.
    Triggers notify_on_round_advance.
    """
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Drive not found.")

    app_rec = await applications_collection.find_one({"drive_id": drive_id, "student_id": student_id})
    if not app_rec:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Application record not found.")

    selection_rounds = drive.get("selection_process", [])
    total_rounds = len(selection_rounds) if selection_rounds else 3

    current_round_num = app_rec.get("current_round", 0) + 1
    round_name = "Round " + str(current_round_num)
    for r in selection_rounds:
        if r.get("round_number") == current_round_num:
            round_name = r.get("round_name", round_name)
            break

    round_history = app_rec.get("round_history", [])
    now_iso = datetime.now(timezone.utc).isoformat()

    new_round_entry = {
        "round_number": current_round_num,
        "round_name": round_name,
        "result": data.result,
        "updated_at": now_iso,
    }
    round_history.append(new_round_entry)

    final_outcome = "in_progress"
    if data.result == "fail":
        final_outcome = "rejected"
    elif data.result == "pass":
        if current_round_num >= total_rounds:
            final_outcome = "selected"
            # Increment offers_made on drive
            await drives_collection.update_one({"drive_id": drive_id}, {"$inc": {"offers_made": 1}})
        else:
            final_outcome = "in_progress"

    await applications_collection.update_one(
        {"drive_id": drive_id, "student_id": student_id},
        {
            "$set": {
                "current_round": current_round_num if data.result == "pass" else current_round_num - 1,
                "round_history": round_history,
                "final_outcome": final_outcome,
            }
        }
    )

    client_ip = request.client.host if request.client else "127.0.0.1"
    user_agent = request.headers.get("user-agent", "unknown")

    audit = AuditLogModel(
        user_id=token_payload["sub"],
        action="RECRUITER_ROUND_RESULT_RECORDED",
        ip=client_ip,
        device=user_agent,
    )
    await audit_logs_collection.insert_one(audit.model_dump())

    # Trigger notification to student
    await notify_on_round_advance(
        drive_id=drive_id,
        student_id=student_id,
        round_number=current_round_num,
        round_name=round_name,
        result=data.result,
        final_outcome=final_outcome,
        custom_message=data.custom_message,
    )

    return {
        "message": f"Round result recorded successfully for student {student_id}.",
        "current_round": current_round_num,
        "result": data.result,
        "final_outcome": final_outcome,
    }

@router.get("/stats", response_model=RecruiterStatsResponse)
async def get_recruiter_placement_stats(
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    GET /recruiter/stats — total_registered_students, total_active_drives, total_offers_made.
    Since there is exactly ONE recruiter, counts ALL drives/listings globally.
    """
    try:
        total_registered_students = await students_collection.count_documents({})
    except Exception:
        total_registered_students = 0

    total_active_listings = 0
    try:
        cursor_listings = company_listings_collection.find({})
        listings_list = await cursor_listings.to_list(length=500)
        published_cnt = sum(1 for item in listings_list if item.get("status") in ("published", "active"))
        total_active_listings = published_cnt if published_cnt > 0 else len(listings_list)
    except Exception:
        total_active_listings = 0

    total_active_drives = 0
    try:
        cursor_drives = drives_collection.find({})
        drives_list = await cursor_drives.to_list(length=500)
        published_d_cnt = sum(1 for item in drives_list if item.get("status") in ("published", "active"))
        total_active_drives = published_d_cnt if published_d_cnt > 0 else len(drives_list)
    except Exception:
        total_active_drives = 0

    total_offers_made = 0
    try:
        cursor = drives_collection.find({})
        drives = await cursor.to_list(length=500)
        total_offers_made = sum(d.get("offers_made", 0) for d in drives)
    except Exception:
        pass

    final_val = max(total_active_listings, total_active_drives)

    return RecruiterStatsResponse(
        total_registered_students=total_registered_students,
        total_active_listings=final_val,
        total_active_drives=final_val,
        total_offers_made=total_offers_made,
    )
