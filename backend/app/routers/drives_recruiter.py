import io
import json
import logging
from pathlib import Path
import re
import uuid
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any, Union, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status, File, UploadFile, Form, Request

from app.database import (
    company_listings_collection,
    drives_collection,
    applications_collection,
    students_collection,
    users_collection,
    audit_logs_collection,
    notifications_collection,
    grid_fs,
)
from pydantic import BaseModel, Field
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
    MatchingStudentItem,
)
from app.eligibility import compute_eligibility
from app.notifications import (
    notify_on_publish,
    notify_on_schedule_change,
    notify_on_round_advance,
)
from app.services.skill_matcher import skill_matcher_engine
from app.services.talent_comparator import TalentComparatorService
from app.services.groq_matcher import GroqMatcherService, SmartAIMatchResponse

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
    ctc_min: Union[float, str] = Form(6.0),
    ctc_max: Union[float, str] = Form(12.0),
    stipend: Optional[Union[float, str]] = Form(None),
    description: str = Form(...),
    qualifications: str = Form("B.Tech / BCA"),
    additional_requirements: str = Form(""),
    bond_details: str = Form("No Bond"),
    eligibility_criteria_summary: str = Form("Min CGPA 6.0"),
    min_cgpa: Union[float, str] = Form(6.0),
    schedule_datetime: str = Form(...),
    registration_deadline: str = Form(...),
    status_field: str = Form("published"),
    eligible_courses_json: Optional[str] = Form(None),
    selection_process_json: Optional[str] = Form(None),
    policy_flags_json: Optional[str] = Form(None),
    required_skills_json: Optional[str] = Form(None),
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

    try:
        ctc_min_val = float(ctc_min)
    except (ValueError, TypeError):
        ctc_min_val = 6.0

    try:
        ctc_max_val = float(ctc_max)
    except (ValueError, TypeError):
        ctc_max_val = 12.0

    stipend_val: Optional[float] = None
    if stipend is not None:
        s_str = str(stipend).strip()
        if s_str and s_str.lower() not in ("none", "null", ""):
            try:
                stipend_val = float(s_str)
            except (ValueError, TypeError):
                stipend_val = None

    try:
        min_cgpa_val = float(min_cgpa)
    except (ValueError, TypeError):
        min_cgpa_val = 6.0

    # Auto-extract skills using bounded taxonomy PhraseMatcher
    extracted_skills = skill_matcher_engine.extract_skills_from_text(description)
    manual_skills = []
    if required_skills_json:
        try:
            parsed_req = json.loads(required_skills_json)
            if isinstance(parsed_req, list):
                manual_skills = [str(s).strip() for s in parsed_req if str(s).strip()]
        except Exception:
            pass
    combined_req_skills = sorted(list(set(manual_skills + extracted_skills)))

    drive_doc = DriveModel(
        company_name=sanitize_string(company_name),
        company_email=clean_company_email,
        drive_title=sanitize_string(drive_title),
        mode=mode if mode in ["on_campus", "off_campus", "virtual"] else "on_campus",
        employment_type=employment_type if employment_type in ["internship", "full_time", "internship_and_full_time"] else "full_time",
        location=sanitize_string(location),
        school_tag=sanitize_string(school_tag),
        ctc_min=ctc_min_val,
        ctc_max=ctc_max_val,
        stipend=stipend_val,
        description=sanitize_string(description),
        required_skills=combined_req_skills,
        extracted_required_skills=extracted_skills,
        qualifications=sanitize_string(qualifications),
        additional_requirements=sanitize_string(additional_requirements),
        bond_details=sanitize_string(bond_details),
        attachment_pdf_url=pdf_url,
        eligible_courses=eligible_courses,
        eligibility_criteria_summary=sanitize_string(eligibility_criteria_summary),
        min_cgpa=min_cgpa_val,
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

    caller_id = token_payload.get("sub")
    caller_role = token_payload.get("role")
    drive_owner = drive.get("posted_by")
    if caller_role != "admin" and drive_owner and drive_owner != caller_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access forbidden. You can only modify placement drives created by your account."
        )

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

    caller_id = token_payload.get("sub")
    caller_role = token_payload.get("role")
    drive_owner = drive.get("posted_by")
    if caller_role != "admin" and drive_owner and drive_owner != caller_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access forbidden. You can only publish placement drives created by your account."
        )

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
            description=str(d.get("description", "") or ""),
            location=str(d.get("location", "") or d.get("interview_venue", "") or ""),
            mode=str(d.get("mode", "on_campus") or "on_campus"),
            company_email=str(d.get("company_email", "") or ""),
            bond_details=str(d.get("bond_details", "") or d.get("bond_time", "") or ""),
            bond_time=str(d.get("bond_time", "") or d.get("bond_details", "") or ""),
            schedule_datetime=str(d.get("schedule_datetime", "") or d.get("interview_datetime", "") or ""),
            interview_datetime=str(d.get("interview_datetime", "") or d.get("schedule_datetime", "") or ""),
            registration_deadline=str(d.get("registration_deadline", "") or ""),
            required_skills=list(d.get("required_skills", []) or []),
            preferred_skills=list(d.get("preferred_skills", []) or []),
            attachment_pdf_url=d.get("attachment_pdf_url") or d.get("pdf_url"),
            pdf_url=d.get("pdf_url") or d.get("attachment_pdf_url"),
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
        "notes": data.custom_message or "",
        "feedback": data.custom_message or "",
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


class OfferSetupRequest(BaseModel):
    ctc: str = Field(..., description="Offered CTC e.g. 20 LPA or ₹20,00,000")
    base_salary: Optional[str] = "₹16,00,000 / year"
    bonus: Optional[str] = "₹2,00,000 performance bonus"
    stocks: Optional[str] = "Optional RSUs / ESOPs"
    role_title: Optional[str] = None
    joining_date: Optional[str] = "2026-07-01"
    acceptance_deadline: Optional[str] = "2026-07-15"
    location: Optional[str] = "Bangalore, India"
    work_mode: Optional[str] = "Hybrid (3 days in office)"
    probation_period: Optional[str] = "3 Months"
    bond_terms: Optional[str] = "No bond / Service agreement"
    special_notes: Optional[str] = "Congratulations on successfully clearing all placement evaluation rounds!"
    offer_letter_url: Optional[str] = None


@router.post("/drives/{drive_id}/applications/{student_id}/offer", status_code=status.HTTP_200_OK)
async def setup_placement_offer(
    drive_id: str,
    student_id: str,
    data: OfferSetupRequest,
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    Recruiter sets up / configures a placement offer for a student candidate.
    Persists to applications_collection, sets final_outcome="selected",
    increments drive offers_made, and dispatches in-app notification.
    """
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Placement drive not found.")

    app_rec = await applications_collection.find_one({"drive_id": drive_id, "student_id": student_id})
    now_iso = datetime.now(timezone.utc).isoformat()
    if not app_rec:
        # Create an application record so recruiter can issue direct offer
        app_id = f"app_{uuid.uuid4().hex[:12]}"
        app_rec = {
            "app_id": app_id,
            "drive_id": drive_id,
            "student_id": student_id,
            "applied_at": now_iso,
            "status": "applied",
            "current_round": 1,
            "round_history": [],
            "final_outcome": "selected",
        }
        await applications_collection.insert_one(app_rec)

    company_name = drive.get("company_name", "Company")
    role_title = data.role_title or drive.get("drive_title") or drive.get("interview_job", "Placement Position")

    offer_details = {
        "ctc": data.ctc,
        "base_salary": data.base_salary,
        "bonus": data.bonus,
        "stocks": data.stocks,
        "company_name": company_name,
        "role_title": role_title,
        "joining_date": data.joining_date,
        "acceptance_deadline": data.acceptance_deadline,
        "location": data.location,
        "work_mode": data.work_mode,
        "probation_period": data.probation_period,
        "bond_terms": data.bond_terms,
        "special_notes": data.special_notes,
        "offer_letter_url": data.offer_letter_url,
        "status": "pending",
        "issued_at": now_iso,
    }

    # If previously not selected, increment offers_made
    if app_rec.get("final_outcome") not in ("selected", "offered", "accepted"):
        await drives_collection.update_one({"drive_id": drive_id}, {"$inc": {"offers_made": 1}})

    await applications_collection.update_one(
        {"drive_id": drive_id, "student_id": student_id},
        {
            "$set": {
                "final_outcome": "selected",
                "offer_details": offer_details,
                "updated_at": now_iso,
            }
        }
    )

    # Push in-app notification to student
    student_user_id = student_id
    st = await students_collection.find_one({"$or": [{"student_id": student_id}, {"user_id": student_id}]})
    student_email = None
    if st:
        student_user_id = st.get("user_id", student_id)
        student_email = st.get("email")

    notif_doc = {
        "notification_id": f"notif_{uuid.uuid4().hex[:12]}",
        "recipient_id": student_user_id,
        "recipient_email": student_email,
        "user_id": student_user_id,
        "title": "🎉 Official Placement Offer Extended!",
        "message": f"Congratulations! {company_name} has extended an official placement offer for {role_title} with CTC {data.ctc}.",
        "type": "placement_offer",
        "is_read": False,
        "created_at": datetime.now(timezone.utc),
    }
    await notifications_collection.insert_one(notif_doc)

    return {
        "message": f"Placement offer successfully configured and issued to student for {company_name}.",
        "drive_id": drive_id,
        "student_id": student_id,
        "offer_details": offer_details,
    }




@router.get("/drives/{drive_id}/matching-students", response_model=PaginatedResponse[MatchingStudentItem])
async def get_matching_students_for_drive(
    drive_id: str,
    request: Request,
    match_type: Literal["any", "all"] = Query("any", description="'any' to match any skill, 'all' to match all required skills"),
    min_cgpa: Optional[float] = Query(None, ge=0.0, le=10.0, description="Optional minimum CGPA filter"),
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(20, ge=1, le=100, description="Items per page"),
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    GET /recruiter/drives/{drive_id}/matching-students
    Direct exact skill presence/absence matching against all registered students.
    Returns matched candidates with matched/missing chips, match count, sorted by (match_count DESC, cgpa DESC).
    """
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Drive not found.")

    required_skills = drive.get("extracted_required_skills") or []
    if not required_skills:
        manual_req = drive.get("required_skills") or []
        extracted = skill_matcher_engine.extract_skills_from_text(drive.get("description", ""))
        required_skills = sorted(list(set(manual_req + extracted)))

    if not required_skills:
        return PaginatedResponse(items=[], page=page, limit=limit, total_count=0, has_more=False)

    # Build native MongoDB query with case-variant awareness
    query: Dict[str, Any] = {}
    if match_type == "all":
        # Every required skill must be present in at least one casing variant
        query["$and"] = [
            {"skills": {"$in": [s, s.lower(), s.title(), s.upper()]}}
            for s in required_skills
        ]
    else:
        # Match any required skill across common casing variants
        variant_set = set(required_skills)
        for s in required_skills:
            variant_set.add(s.lower())
            variant_set.add(s.title())
            variant_set.add(s.upper())
        query["skills"] = {"$in": list(variant_set)}

    effective_cgpa = min_cgpa if min_cgpa is not None else drive.get("min_cgpa")
    if effective_cgpa is not None and effective_cgpa > 0:
        query["$or"] = [
            {"CGPA": {"$gte": effective_cgpa}},
            {"cgpa": {"$gte": effective_cgpa}}
        ]

    cursor = students_collection.find(query)
    candidates = await cursor.to_list(length=1000)

    # Pre-fetch missing user emails to eliminate N+1 queries
    missing_user_ids = [c["user_id"] for c in candidates if not c.get("email") and c.get("user_id")]
    user_email_map: Dict[str, str] = {}
    if missing_user_ids:
        u_cursor = users_collection.find({"user_id": {"$in": missing_user_ids}}, {"user_id": 1, "email": 1})
        u_list = await u_cursor.to_list(length=len(missing_user_ids) + 1)
        user_email_map = {u["user_id"]: u.get("email", "") for u in u_list if "user_id" in u and u.get("email")}

    matched_items: List[MatchingStudentItem] = []
    for cand in candidates:
        cand_skills = cand.get("skills", [])
        overlap = skill_matcher_engine.compute_skill_overlap(cand_skills, required_skills)
        if match_type == "all" and not overlap["is_exact_match"]:
            continue
        if match_type == "any" and overlap["match_count"] == 0:
            continue

        cgpa_val = float(cand.get("CGPA") or cand.get("cgpa") or 0.0)
        email = cand.get("email") or user_email_map.get(cand.get("user_id"))

        matched_items.append(
            MatchingStudentItem(
                student_id=str(cand.get("student_id") or cand.get("user_id") or ""),
                name=cand.get("full_name") or "Student Candidate",
                email=email,
                branch=cand.get("branch") or cand.get("education") or "Engineering",
                cgpa=cgpa_val,
                skills=cand_skills,
                matched_skills=overlap["matched_skills"],
                missing_skills=overlap["missing_skills"],
                match_count=overlap["match_count"],
                total_required=overlap["total_required"],
                resume_url=cand.get("resume_url"),
                has_resume=bool(cand.get("has_resume") or cand.get("resume_url")),
            )
        )

    # Sort descending by (match_count DESC, cgpa DESC)
    matched_items.sort(key=lambda x: (x.match_count, x.cgpa), reverse=True)

    total_count = len(matched_items)
    start_idx = (page - 1) * limit
    paged_items = matched_items[start_idx : start_idx + limit]
    has_more = (start_idx + limit) < total_count

    # Audit log
    client_ip = request.client.host if request.client else "127.0.0.1"
    user_agent = request.headers.get("user-agent", "unknown")
    audit = AuditLogModel(
        user_id=token_payload["sub"],
        action="RECRUITER_SKILL_MATCH_ACCESSED",
        ip=client_ip,
        device=user_agent,
    )
    await audit_logs_collection.insert_one(audit.model_dump())

    return PaginatedResponse(
        items=paged_items,
        page=page,
        limit=limit,
        total_count=total_count,
        has_more=has_more,
    )


@router.get("/drives/{drive_id}/talent-comparison")
async def get_drive_talent_comparison(
    drive_id: str,
    request: Request,
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    GET /recruiter/drives/{drive_id}/talent-comparison
    Compares and ranks matching applicants or eligible students based on:
    1. Core Technical Skills (40%)
    2. Deployment & DevOps Knowledge (30%)
    3. Number of Internships (30%)
    """
    # 1. Fetch Drive
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        drive = await company_listings_collection.find_one({"$or": [{"listing_id": drive_id}, {"drive_id": drive_id}]})
    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Drive or listing not found.")

    company_name = drive.get("company_name", "Company")
    drive_title = drive.get("drive_title") or drive.get("interview_job") or "Placement Drive"
    required_skills = drive.get("required_skills") or []
    if not required_skills:
        required_skills = ["Communication", "Problem Solving", "Software Engineering"]

    # 2. Collect Candidate Profiles: First check applicants, fallback to all registered students
    apps = await applications_collection.find({"drive_id": drive_id}).to_list(length=1000)
    student_ids = [a.get("student_id") for a in apps if a.get("student_id")]

    students = []
    if student_ids:
        cursor = students_collection.find({"$or": [{"student_id": {"$in": student_ids}}, {"user_id": {"$in": student_ids}}]})
        students = await cursor.to_list(length=1000)

    if not students:
        # Fallback: Load registered students for pre-application talent scouting
        cursor = students_collection.find({}).limit(50)
        students = await cursor.to_list(length=50)

    # 3. Rank Candidates via TalentComparatorService
    ranked = TalentComparatorService.rank_candidates(students, required_skills)

    # 4. Audit Log
    client_ip = request.client.host if request.client else "127.0.0.1"
    user_agent = request.headers.get("user-agent", "unknown")
    audit = AuditLogModel(
        user_id=token_payload["sub"],
        action="RECRUITER_TALENT_COMPARISON_ACCESSED",
        ip=client_ip,
        device=user_agent,
    )
    await audit_logs_collection.insert_one(audit.model_dump())

    return {
        "drive_id": drive_id,
        "company_name": company_name,
        "drive_title": drive_title,
        "required_skills": required_skills,
        "total_evaluated": len(ranked),
        "candidates": ranked,
    }


@router.get("/drives/{drive_id}/applicants/{student_id}/ai-insight", status_code=status.HTTP_200_OK, response_model=SmartAIMatchResponse)
async def get_applicant_ai_insight(
    drive_id: str,
    student_id: str,
    request: Request,
    bypass_cache: bool = Query(False, description="Force re-computation with Groq"),
    token_payload: dict = Depends(require_role("recruiter")),
):
    """
    GET /recruiter/drives/{drive_id}/applicants/{student_id}/ai-insight
    Returns the 30-second Recruiter Screening Cheat Sheet, project depth analysis,
    semantic equivalences, and predicted interview questions to ask the candidate.
    """
    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        drive = await company_listings_collection.find_one({"$or": [{"listing_id": drive_id}, {"drive_id": drive_id}]})
    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Drive or listing not found.")

    student_doc = (
        await students_collection.find_one({"student_id": student_id})
        or await students_collection.find_one({"user_id": student_id})
        or await students_collection.find_one({"email": student_id})
        or await users_collection.find_one({"user_id": student_id})
        or await users_collection.find_one({"email": student_id})
    )
    if student_doc and "skills" not in student_doc:
        linked_student = await students_collection.find_one({
            "$or": [
                {"user_id": student_doc.get("user_id")},
                {"email": student_doc.get("email")},
            ]
        })
        if linked_student:
            student_doc = linked_student

    if not student_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Candidate profile not found.")

    # Audit log
    client_ip = request.client.host if request.client else "127.0.0.1"
    user_agent = request.headers.get("user-agent", "unknown")
    audit = AuditLogModel(
        user_id=token_payload["sub"],
        action="RECRUITER_AI_CANDIDATE_INSIGHT_ACCESSED",
        ip=client_ip,
        device=user_agent,
    )
    await audit_logs_collection.insert_one(audit.model_dump())

    # Retrieve application context for multi-round progression
    app = await applications_collection.find_one({
        "$or": [
            {"drive_id": drive_id, "student_id": student_id},
            {"listing_id": drive_id, "student_id": student_id},
            {"drive_id": drive_id, "user_id": student_id},
            {"listing_id": drive_id, "user_id": student_id},
        ]
    })
    current_round = int(app.get("current_round", 1)) if app else 1
    round_history = app.get("round_history", []) if app else []

    return await GroqMatcherService.analyze_match(
        student_doc=student_doc,
        drive_doc=drive,
        current_round=current_round,
        round_history=round_history,
        bypass_cache=bypass_cache,
    )

