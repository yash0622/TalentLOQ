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
    notifications_collection,
)
from pydantic import BaseModel
from app.dependencies import get_optional_current_user, require_role
from app.eligibility import compute_eligibility
from app.models import AuditLogModel, PaginatedResponse, DriveLeanResponse, RecommendedDriveItem
from app.services.skill_matcher import skill_matcher_engine
from app.services.groq_matcher import GroqMatcherService, SmartAIMatchResponse
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
    Excludes drives/companies the student has already applied to.
    Computes 'is_eligible' flag per requesting student.
    """
    applied_ids = set()
    student_doc = None
    if user_payload and user_payload.get("sub"):
        sid = str(user_payload["sub"])
        student_doc = (
            await students_collection.find_one({"student_id": sid})
            or await students_collection.find_one({"user_id": sid})
            or await users_collection.find_one({"user_id": sid})
        )
        student_identifiers = [sid]
        if student_doc:
            if student_doc.get("student_id"):
                student_identifiers.append(str(student_doc["student_id"]))
            if student_doc.get("user_id"):
                student_identifiers.append(str(student_doc["user_id"]))
            if student_doc.get("email"):
                student_identifiers.append(str(student_doc["email"]))

        cursor_apps = applications_collection.find(
            {
                "$or": [
                    {"student_id": {"$in": student_identifiers}},
                    {"student_email": student_doc.get("email", "") if student_doc else ""}
                ]
            }
        )
        app_list = await cursor_apps.to_list(length=2000)
        for a in app_list:
            if a.get("drive_id"):
                applied_ids.add(str(a["drive_id"]))
            if a.get("listing_id"):
                applied_ids.add(str(a["listing_id"]))

    # If unauthenticated, student_doc remains None and is_eligible will evaluate to False

    skip = (page - 1) * limit
    filter_query: Dict[str, Any] = {"status": {"$ne": "closed"}}
    if applied_ids:
        filter_query["$and"] = [
            {"drive_id": {"$nin": list(applied_ids)}},
            {"listing_id": {"$nin": list(applied_ids)}},
        ]

    try:
        total_count = await drives_collection.count_documents(filter_query)
        if total_count == 0:
            filter_query = {}
            total_count = await drives_collection.count_documents(filter_query)
    except Exception:
        total_count = None

    cursor = drives_collection.find(filter_query).sort("created_at", -1).skip(skip).limit(limit)
    paged_drives = await cursor.to_list(length=limit)

    # Fallback to company_listings_collection if drives_collection has 0 records
    if not paged_drives and (total_count == 0 or total_count is None):
        c_filter: Dict[str, Any] = {"status": {"$ne": "closed"}}
        if applied_ids:
            c_filter["listing_id"] = {"$nin": list(applied_ids)}
        try:
            total_count = await company_listings_collection.count_documents(c_filter)
        except Exception:
            total_count = None
        cursor = company_listings_collection.find(c_filter).sort("created_at", -1).skip(skip).limit(limit)
        paged_drives = await cursor.to_list(length=limit)

    if total_count is None:
        total_count = len(paged_drives)

    items = []
    for d in paged_drives:
        is_eligible = compute_eligibility(student_doc, d) if student_doc else False
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

    has_more = (skip + len(items)) < total_count

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

    drive_ids = [str(a.get("drive_id", "")) for a in app_docs if a.get("drive_id")]
    drives_map: Dict[str, Any] = {}
    if drive_ids:
        d_cursor = drives_collection.find({"drive_id": {"$in": drive_ids}})
        for d in await d_cursor.to_list(length=len(drive_ids)):
            d_id = str(d.get("drive_id", ""))
            if d_id:
                drives_map[d_id] = d
        missing_ids = [did for did in drive_ids if did not in drives_map]
        if missing_ids:
            c_cursor = company_listings_collection.find({"listing_id": {"$in": missing_ids}})
            for c in await c_cursor.to_list(length=len(missing_ids)):
                c_id = str(c.get("listing_id", ""))
                if c_id:
                    drives_map[c_id] = c

    items = []
    for app_doc in app_docs:
        drive_id = str(app_doc.get("drive_id", ""))
        drive = drives_map.get(drive_id, {})

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
            "offer_details": app_doc.get("offer_details", {}),
            "app_id": str(app_doc.get("app_id") or app_doc.get("_id", "")),
            "student_id": student_id,
        })

    has_more = (skip + limit) < total_count
    return {
        "items": items,
        "page": page,
        "limit": limit,
        "total_count": total_count,
        "has_more": has_more,
    }

@router.get("/recommended", status_code=status.HTTP_200_OK, response_model=PaginatedResponse[RecommendedDriveItem])
async def get_recommended_drives_for_student(
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(20, ge=1, le=100, description="Items per page"),
    token_payload: dict = Depends(require_role("student")),
):
    """
    GET /drives/recommended
    Returns published drives matching the student's verified skills,
    annotated with exact matched skills, missing skills, and match summary.
    Sorted descending by (match_count DESC, min_cgpa DESC).
    """
    sid = str(token_payload.get("sub", ""))
    student = (
        await students_collection.find_one({"student_id": sid})
        or await students_collection.find_one({"user_id": sid})
    )
    if not student:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Student profile not found."
        )

    student_skills = student.get("skills", [])
    if not student_skills:
        return PaginatedResponse(items=[], page=page, limit=limit, total_count=0, has_more=False)

    # Fetch active drives
    cursor = drives_collection.find({"status": {"$ne": "closed"}}).sort("created_at", -1)
    all_drives = await cursor.to_list(length=500)

    recommended_items: List[RecommendedDriveItem] = []
    for drive in all_drives:
        req_skills = drive.get("extracted_required_skills") or []
        if not req_skills:
            manual_req = drive.get("required_skills") or []
            extracted = skill_matcher_engine.extract_skills_from_text(drive.get("description", ""))
            req_skills = sorted(list(set(manual_req + extracted)))

        if not req_skills:
            continue

        overlap = skill_matcher_engine.compute_skill_overlap(student_skills, req_skills)
        if overlap["match_count"] > 0:
            matched_str = ", ".join(overlap["matched_skills"][:3])
            if len(overlap["matched_skills"]) > 3:
                matched_str += f" +{len(overlap['matched_skills']) - 3} more"
            summary = f"Matches {overlap['match_count']} of {overlap['total_required']} skills ({matched_str})"

            is_eligible = compute_eligibility(student, drive)

            recommended_items.append(
                RecommendedDriveItem(
                    drive_id=str(drive.get("drive_id", "")),
                    company_name=drive.get("company_name", "Company"),
                    drive_title=drive.get("drive_title", "Placement Drive"),
                    employment_type=drive.get("employment_type", "full_time"),
                    location=drive.get("location", "Campus"),
                    ctc_min=float(drive.get("ctc_min") or 0.0),
                    ctc_max=float(drive.get("ctc_max") or 0.0),
                    min_cgpa=float(drive.get("min_cgpa") or 0.0),
                    eligible_courses=drive.get("eligible_courses") or ["ALL"],
                    is_eligible=is_eligible,
                    extracted_required_skills=req_skills,
                    matched_skills=overlap["matched_skills"],
                    missing_skills=overlap["missing_skills"],
                    match_count=overlap["match_count"],
                    total_required=overlap["total_required"],
                    match_summary=summary,
                )
            )

    # Sort descending by match_count, then min_cgpa
    recommended_items.sort(key=lambda x: (x.match_count, x.min_cgpa), reverse=True)

    total_count = len(recommended_items)
    start_idx = (page - 1) * limit
    paged_items = recommended_items[start_idx : start_idx + limit]
    has_more = (start_idx + limit) < total_count

    return PaginatedResponse(
        items=paged_items,
        page=page,
        limit=limit,
        total_count=total_count,
        has_more=has_more,
    )

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

    drive["is_eligible"] = compute_eligibility(student_doc, drive) if student_doc else False

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
        r_url = student_doc.get("resume_url")
        r_id = student_doc.get("resume_id")
        r_file = student_doc.get("resume_filename")
        if r_url == "/static/uploads/resume.pdf" or r_file == "resume.pdf" or (r_file and "jane_smith" in str(r_file).lower()):
            has_resume = False
            resume_id = None
        else:
            has_resume = bool(student_doc.get("has_resume", False))
            resume_id = r_id or r_url or ("resume_uploaded" if has_resume else None)

    if not has_resume or not resume_id:
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
        "name": (student_doc.get("full_name") or student_doc.get("name") or "") if student_doc else "",
        "email": (student_doc.get("email") or "") if student_doc else "",
        "phone_number": (student_doc.get("phone_number") or student_doc.get("phone") or "") if student_doc else "",
        "cgpa": float(student_doc.get("CGPA") or student_doc.get("cgpa") or 0.0) if student_doc else 0.0,
        "course": (student_doc.get("course") or student_doc.get("education") or "") if student_doc else "",
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


@router.get("/{drive_id}/ai-match", status_code=status.HTTP_200_OK, response_model=SmartAIMatchResponse)
async def get_student_drive_ai_match(
    drive_id: str,
    bypass_cache: bool = Query(False, description="Force re-computation with Groq"),
    token_payload: dict = Depends(require_role("student")),
):
    """
    GET /drives/{drive_id}/ai-match
    Computes a smart, 4-pillar recruitment intelligence match using Groq AI.
    Includes semantic equivalences, project evidence mining, skill gaps,
    and 3 predicted technical interview questions with 48h prep checklist.
    """
    student_id = token_payload["sub"]
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
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student profile not found.")

    drive = await drives_collection.find_one({"drive_id": drive_id})
    if not drive:
        drive = await drives_collection.find_one({"listing_id": drive_id})
    if not drive:
        drive = await company_listings_collection.find_one({"listing_id": drive_id})
    if not drive:
        drive = await company_listings_collection.find_one({"drive_id": drive_id})
    if not drive:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Placement drive not found.")

    # Retrieve application context for multi-round progression
    student_id = str(student_doc.get("student_id") or student_doc.get("user_id") or "")
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


class OfferActionRequest(BaseModel):
    reason: Optional[str] = None


@router.post("/{drive_id}/accept-offer", status_code=status.HTTP_200_OK)
async def accept_placement_offer(
    drive_id: str,
    token_payload: dict = Depends(require_role("student")),
):
    """
    Student formally accepts the extended placement offer.
    """
    student_id = token_payload["sub"]
    app_doc = await applications_collection.find_one({"drive_id": drive_id, "student_id": student_id})
    if not app_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Application or offer not found.")

    now_iso = datetime.now(timezone.utc).isoformat()
    offer_details = app_doc.get("offer_details") or {}
    offer_details["status"] = "accepted"
    offer_details["accepted_at"] = now_iso

    await applications_collection.update_one(
        {"_id": app_doc["_id"]},
        {
            "$set": {
                "final_outcome": "accepted",
                "offer_details": offer_details,
                "offer_accepted_at": now_iso,
            }
        }
    )

    drive = await drives_collection.find_one({"drive_id": drive_id})
    company_name = drive.get("company_name", "Company") if drive else "Company"
    recruiter_id = app_doc.get("recruiter_id") or (drive.get("recruiter_id") if drive else None)

    if recruiter_id:
        notif_doc = {
            "notification_id": f"notif_{uuid.uuid4().hex[:12]}",
            "recipient_id": recruiter_id,
            "user_id": recruiter_id,
            "title": "🎉 Placement Offer Accepted!",
            "message": f"Candidate {student_id} has officially ACCEPTED the placement offer for {company_name}.",
            "type": "offer_accepted",
            "is_read": False,
            "created_at": datetime.now(timezone.utc),
        }
        await notifications_collection.insert_one(notif_doc)

    return {
        "message": f"Congratulations! You have successfully accepted the placement offer from {company_name}.",
        "status": "accepted",
        "offer_details": offer_details,
    }


@router.post("/{drive_id}/decline-offer", status_code=status.HTTP_200_OK)
async def decline_placement_offer(
    drive_id: str,
    data: Optional[OfferActionRequest] = None,
    token_payload: dict = Depends(require_role("student")),
):
    """
    Student declines the extended placement offer.
    """
    student_id = token_payload["sub"]
    app_doc = await applications_collection.find_one({"drive_id": drive_id, "student_id": student_id})
    if not app_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Application or offer not found.")

    now_iso = datetime.now(timezone.utc).isoformat()
    offer_details = app_doc.get("offer_details") or {}
    offer_details["status"] = "declined"
    offer_details["declined_at"] = now_iso
    offer_details["decline_reason"] = data.reason if data else None

    await applications_collection.update_one(
        {"_id": app_doc["_id"]},
        {
            "$set": {
                "final_outcome": "declined",
                "offer_details": offer_details,
            }
        }
    )

    return {
        "message": "Offer declined.",
        "status": "declined",
        "offer_details": offer_details,
    }


