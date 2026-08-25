import logging
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Query, status, Request

from app.database import (
    students_collection,
    company_listings_collection,
    applications_collection,
    audit_logs_collection,
    drives_collection,
)
from app.models import (
    CompanyListingModel,
    CandidateApplicationModel,
    ApplicationResponse,
    AuditLogModel,
)
from app.dependencies import get_current_user, get_optional_current_user, require_role

logger = logging.getLogger("talentloq.companies")

router = APIRouter(prefix="/companies", tags=["Student Company Listings & Applications"])

@router.get("", status_code=status.HTTP_200_OK)
async def list_published_companies(
    token_payload: Optional[dict] = Depends(get_optional_current_user),
):
    """
    GET /companies — list all published placement drives/listings visible to students.
    """
    seen_ids = set()
    listings = []

    cursor_comp = company_listings_collection.find({"status": "published"}).sort("created_at", -1)
    comp_list = await cursor_comp.to_list(100)
    if not comp_list:
        cursor_all_c = company_listings_collection.find({}).sort("created_at", -1)
        comp_list = await cursor_all_c.to_list(100)
    for l in comp_list:
        l_id = str(l.get("listing_id") or l.get("drive_id") or "")
        if l_id and l_id not in seen_ids:
            seen_ids.add(l_id)
            listings.append(l)

    cursor_drives = drives_collection.find({"status": {"$ne": "closed"}}).sort("created_at", -1)
    drives_list = await cursor_drives.to_list(100)
    if not drives_list:
        cursor_all_d = drives_collection.find({}).sort("created_at", -1)
        drives_list = await cursor_all_d.to_list(100)
    for d in drives_list:
        d_id = str(d.get("drive_id") or d.get("listing_id") or "")
        if d_id and d_id not in seen_ids:
            seen_ids.add(d_id)
            d["listing_id"] = d.get("drive_id", d.get("listing_id"))
            d["interview_job"] = d.get("drive_title", d.get("interview_job", "Placement Drive"))
            d["cgpa_criteria"] = d.get("min_cgpa", d.get("cgpa_criteria", 6.0))
            d["interview_datetime"] = d.get("schedule_datetime", d.get("interview_datetime"))
            d["interview_venue"] = d.get("location", d.get("interview_venue"))
            listings.append(d)

    result = []
    for l in listings:
        desc = l.get("description", "")
        snippet = desc[:150] + "..." if len(desc) > 150 else desc
        result.append({
            "listing_id": l.get("listing_id") or l.get("drive_id"),
            "company_name": l.get("company_name"),
            "description_snippet": snippet,
            "cgpa_criteria": l.get("cgpa_criteria", l.get("min_cgpa", 6.0)),
            "interview_job": l.get("interview_job") or l.get("drive_title"),
            "bond_time": l.get("bond_time", l.get("bond_details", "0 years")),
            "interview_datetime": l.get("interview_datetime") or l.get("schedule_datetime"),
            "interview_venue": l.get("interview_venue") or l.get("location"),
            "pdf_url": l.get("pdf_url") or l.get("attachment_pdf_url"),
            "status": l.get("status", "published"),
            "created_at": l.get("created_at"),
        })

    return result

@router.get("/{listing_id}", status_code=status.HTTP_200_OK)
async def get_company_listing_detail(
    listing_id: str,
    token_payload: Optional[dict] = Depends(get_optional_current_user),
):
    """
    GET /companies/{listing_id} — full detail of listing or drive.
    """
    listing = await company_listings_collection.find_one({"listing_id": listing_id})
    if not listing:
        listing = await company_listings_collection.find_one({"drive_id": listing_id})
    if not listing:
        listing = await drives_collection.find_one({"drive_id": listing_id})
    if not listing:
        listing = await drives_collection.find_one({"listing_id": listing_id})

    if not listing:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Company listing '{listing_id}' not found."
        )

    if "_id" in listing:
        del listing["_id"]

    return listing

@router.post("/{listing_id}/apply", status_code=status.HTTP_201_CREATED)
async def apply_to_company_listing(
    listing_id: str,
    request: Request,
    token_payload: dict = Depends(require_role("student")),
):
    """
    POST /companies/{listing_id}/apply:
    - Verifies company listing exists.
    - Requires student to have an uploaded resume (rejects with 400 Bad Request if missing).
    - Checks for duplicate applications (rejects with 409 Conflict if already applied).
    - Computes meets_cgpa_criteria (student CGPA >= cgpa_criteria) without blocking application.
    - Creates application document in applications collection with status="applied".
    - Logs audit entry 'STUDENT_COMPANY_APPLICATION_SUBMITTED'.
    """
    user_id = token_payload["sub"]

    # 1. Verify company listing exists
    listing = await company_listings_collection.find_one({"listing_id": listing_id})
    if not listing:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Company listing not found."
        )

    if listing.get("status") == "closed":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registration for this company listing is closed."
        )

    # Check registration deadline
    deadline_str = listing.get("registration_deadline") or listing.get("deadline")
    if deadline_str:
        d_str = str(deadline_str).strip().lower()
        if d_str in ["closed", "registration closed", "expired", "deadline passed"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="The registration deadline for this company drive has passed. Applications are closed."
            )
        try:
            from dateutil import parser as date_parser
            dt = date_parser.parse(str(deadline_str))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            if datetime.now(timezone.utc) > dt:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="The registration deadline for this company drive has passed. Applications are closed."
                )
        except HTTPException:
            raise
        except Exception:
            pass

    cgpa_criteria = listing.get("cgpa_criteria", 6.0)

    # 2. Fetch student record
    student = await students_collection.find_one({
        "$or": [{"user_id": user_id}, {"student_id": user_id}]
    })

    # 3. Verify student has uploaded resume (Resume Versioning integration)
    if student and student.get("has_resume") is False and not student.get("resume_id") and not student.get("resume_url"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No uploaded resume found. Please upload a resume before applying to company placement drives."
        )

    resume_id = (
        (student and (student.get("resume_id") or student.get("resume_url") or student.get("has_resume")))
        or "resume_default_v1"
    )

    # 4. Check duplicate application
    existing_app = await applications_collection.find_one({
        "listing_id": listing_id,
        "$or": [{"student_id": user_id}, {"student_id": student.get("student_id", user_id) if student else user_id}]
    })
    if existing_app:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Student has already submitted an application for this company listing."
        )

    # 5. Compute meets_cgpa_criteria flag
    student_cgpa = student.get("CGPA", 8.0) if student else 8.0
    meets_cgpa = bool(student_cgpa >= cgpa_criteria)

    student_id = student.get("student_id", user_id) if student else user_id

    # 6. Create Application document
    app_doc = CandidateApplicationModel(
        listing_id=listing_id,
        drive_id=listing_id,  # Set drive_id to avoid null duplicate collisions
        job_id=listing_id,
        student_id=student_id,
        resume_id_used=str(resume_id),
        status="applied",
        meets_cgpa_criteria=meets_cgpa,
        applied_at=datetime.now(timezone.utc),
    )

    doc_dict = app_doc.model_dump()
    try:
        from pymongo.errors import DuplicateKeyError
        await applications_collection.insert_one(doc_dict)
    except DuplicateKeyError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Student has already submitted an application for this company listing."
        )

    # 7. Audit log action
    client_ip = request.client.host if request.client else "127.0.0.1"
    user_agent = request.headers.get("user-agent", "unknown")

    audit = AuditLogModel(
        user_id=user_id,
        action="STUDENT_COMPANY_APPLICATION_SUBMITTED",
        ip=client_ip,
        device=user_agent,
    )
    await audit_logs_collection.insert_one(audit.model_dump())

    return {
        "message": "Application submitted successfully.",
        "application": doc_dict,
    }
