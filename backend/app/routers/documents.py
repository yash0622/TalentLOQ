"""
Document Verification API Router.
Endpoints:
- POST /documents/upload
- GET /documents
- GET /documents/{document_id}/status
- PUT /documents/{document_id}/replace
- GET /profile/verification
- POST /documents/{document_id}/review-action (Admin / Reviewer)
"""
import io
import uuid
import logging
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from pydantic import BaseModel

logger = logging.getLogger("talentloq.documents")
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status, BackgroundTasks
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from bson import ObjectId

from app.jwt_utils import decode_token
from app.dependencies import require_roles
from app.database import (
    async_db,
    students_collection,
    users_collection,
    verification_documents_collection,
    verification_audits_collection,
    support_tickets_collection,
    grid_fs,
)
from app.document_detection import (
    DocumentVerificationService,
    )

router = APIRouter(prefix="/documents", tags=["Document Verification"])
security_bearer = HTTPBearer(auto_error=False)


async def get_current_user_id(credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_bearer)) -> str:
    """Extracts sub from JWT bearer or raises 401."""
    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required to manage documents.",
        )
    try:
        payload = decode_token(credentials.credentials, expected_type="access")
        sub = payload.get("sub")
        if not sub:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token subject.")
        return sub
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=f"Token verification failed: {e}")


@router.post("/upload")
async def upload_document(
    file: UploadFile = File(...),
    target_type: Optional[str] = Form(None),  # RESUME, TENTH_MARKSHEET, TWELFTH_OR_DIPLOMA, UG_MARKSHEET
    user_id: str = Depends(get_current_user_id),
):
    """
    Uploads an academic document (PDF, PNG, JPG) and triggers the OCR & verification pipeline.
    Automatically extracts fields, verifies authenticity, detects changes via SHA-256,
    and updates the canonical student profile when verified.
    """
    try:
        result = await DocumentVerificationService.process_document_upload(
            file=file,
            user_id=user_id,
            target_type=target_type,
        )
        return {
            "message": f"Document processed with status: {result.status.value}",
            "document_id": result.document_id,
            "document_type": result.document_type.value,
            "status": result.status.value,
            "overall_confidence": result.overall_confidence,
            "ocr_confidence": result.ocr_confidence,
            "extraction_confidence": result.extraction_confidence,
            "validation_confidence": result.validation_confidence,
            "extracted_fields": result.extracted_fields,
            "validation_errors": result.validation_errors,
            "warnings": result.warnings,
            "provenance": result.provenance,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Document processing failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Document processing failed: {str(e)}"
        )


@router.get("")
async def list_user_documents(
    user_id: str = Depends(get_current_user_id),
):
    """
    Lists all uploaded verification documents for the authenticated student.
    """
    student_doc = await students_collection.find_one({
        "$or": [{"user_id": user_id}, {"student_id": user_id}, {"email": user_id}]
    })
    student_id = student_doc.get("student_id", user_id) if student_doc else user_id

    cursor = verification_documents_collection.find({"student_id": student_id}).sort("uploaded_at", -1)
    documents = await cursor.to_list(length=100)

    formatted = []
    for doc in documents:
        formatted.append({
            "document_id": doc.get("document_id"),
            "document_type": doc.get("document_type"),
            "target_type": doc.get("target_type"),
            "filename": doc.get("filename"),
            "file_url": doc.get("file_url"),
            "processing_status": doc.get("processing_status"),
            "extracted_data": doc.get("extracted_data", {}),
            "ocr_confidence": doc.get("ocr_confidence", 0.0),
            "extraction_confidence": doc.get("extraction_confidence", 0.0),
            "validation_confidence": doc.get("validation_confidence", 0.0),
            "validation_errors": doc.get("validation_errors", []),
            "warnings": doc.get("warnings", []),
            "uploaded_at": doc.get("uploaded_at"),
            "verified_at": doc.get("verified_at"),
        })

    return {"documents": formatted}


@router.get("/{document_id}/status")
async def get_document_status(
    document_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """
    Polls real-time verification and OCR status of a specific document.
    """
    doc = await verification_documents_collection.find_one({"document_id": document_id})
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found.")

    return {
        "document_id": doc.get("document_id"),
        "document_type": doc.get("document_type"),
        "filename": doc.get("filename"),
        "processing_status": doc.get("processing_status"),
        "ocr_confidence": doc.get("ocr_confidence", 0.0),
        "extraction_confidence": doc.get("extraction_confidence", 0.0),
        "validation_confidence": doc.get("validation_confidence", 0.0),
        "extracted_data": doc.get("extracted_data", {}),
        "validation_errors": doc.get("validation_errors", []),
        "warnings": doc.get("warnings", []),
        "uploaded_at": doc.get("uploaded_at"),
        "verified_at": doc.get("verified_at"),
    }


@router.put("/{document_id}/replace")
async def replace_document(
    document_id: str,
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
):
    """
    Replaces an existing document with a new file.
    Reprocesses OCR and updates canonical student profile.
    """
    old_doc = await verification_documents_collection.find_one({"document_id": document_id})
    if not old_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document to replace not found.")

    doc_owner = str(old_doc.get("user_id") or old_doc.get("student_id") or "")
    if doc_owner and doc_owner != str(user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to replace this document."
        )

    target_type = old_doc.get("target_type") or old_doc.get("document_type")

    # Mark old document as REPLACED
    await verification_documents_collection.update_one(
        {"document_id": document_id},
        {"$set": {"processing_status": "REPLACED"}}
    )

    # Process new document
    result = await DocumentVerificationService.process_document_upload(
        file=file,
        user_id=user_id,
        target_type=target_type,
    )

    return {
        "message": "Document replaced and verified successfully.",
        "old_document_id": document_id,
        "new_document_id": result.document_id,
        "status": result.status.value,
        "overall_confidence": result.overall_confidence,
        "extracted_fields": result.extracted_fields,
    }


@router.delete("/{document_id}")
async def delete_document(
    document_id: str,
    target_type: Optional[str] = None,
    user_id: str = Depends(get_current_user_id),
):
    """
    Permanently deletes a verification document and instantly resets/clears
    all verified profile values associated with that document from the student profile.
    """
    student_doc = await students_collection.find_one({
        "$or": [{"user_id": user_id}, {"student_id": user_id}, {"email": user_id}]
    })
    if not student_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student profile not found.")

    doc = await verification_documents_collection.find_one({
        "document_id": document_id,
        "$or": [{"user_id": user_id}, {"student_id": user_id}]
    })

    if not doc and not target_type and document_id not in ["TENTH_MARKSHEET", "TWELFTH_MARKSHEET", "DIPLOMA_CERTIFICATE", "DIPLOMA_MARKSHEET", "UG_MARKSHEET", "UG_MARK_SHEET", "RESUME", "TWELFTH_OR_DIPLOMA"]:
        other_user_doc = await verification_documents_collection.find_one({"document_id": document_id})
        if other_user_doc:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You do not have permission to delete this document.")
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found.")

    doc_type = None
    grid_file_id = None
    if doc:
        doc_type = doc.get("target_type") or doc.get("document_type")
        grid_file_id = doc.get("grid_file_id")
        await verification_documents_collection.delete_one({"_id": doc["_id"]})
    elif target_type:
        doc_type = target_type
    elif document_id in ["TENTH_MARKSHEET", "TWELFTH_MARKSHEET", "DIPLOMA_CERTIFICATE", "DIPLOMA_MARKSHEET", "UG_MARKSHEET", "UG_MARK_SHEET", "RESUME", "TWELFTH_OR_DIPLOMA"]:
        doc_type = document_id

    if not doc and doc_type:
        await verification_documents_collection.delete_many({
            "$and": [
                {"$or": [{"user_id": user_id}, {"student_id": user_id}]},
                {"$or": [{"target_type": doc_type}, {"document_type": doc_type}]}
            ]
        })

    # Clean up GridFS if grid_file_id exists using shared database client
    if grid_file_id:
        try:
            import motor.motor_asyncio
            from app.database import database
            grid_bucket = motor.motor_asyncio.AsyncIOMotorGridFSBucket(database)
            await grid_bucket.delete(ObjectId(grid_file_id))
        except Exception:
            pass

    # Instantly reset/clear all verified fields associated with this document type
    set_fields: Dict[str, Any] = {}
    verified_fields = student_doc.get("verified_fields", {})
    doc_summaries = student_doc.get("documents", {})

    if doc_type in ["TENTH_MARKSHEET", "TENTH"]:
        set_fields["tenth_percentage"] = None
        set_fields["tenth_cgpa"] = None
        set_fields["tenth_board"] = None
        set_fields["tenth_passing_year"] = None
        verified_fields.pop("tenth_percentage", None)
        verified_fields.pop("tenth_cgpa", None)
        verified_fields.pop("tenth_board", None)
        verified_fields.pop("tenth_passing_year", None)
        doc_summaries.pop("tenth", None)

    elif doc_type in ["TWELFTH_MARKSHEET", "DIPLOMA_CERTIFICATE", "DIPLOMA_MARKSHEET", "TWELFTH_OR_DIPLOMA"]:
        set_fields["twelfth_percentage"] = None
        set_fields["twelfth_board"] = None
        set_fields["twelfth_passing_year"] = None
        set_fields["diploma_cgpa"] = None
        set_fields["diploma_college"] = None
        verified_fields.pop("twelfth_percentage", None)
        verified_fields.pop("diploma_cgpa", None)
        verified_fields.pop("twelfth_board", None)
        verified_fields.pop("diploma_college", None)
        doc_summaries.pop("twelfth_diploma", None)

    elif doc_type in ["UG_MARKSHEET", "UG_MARK_SHEET", "DEGREE_CERTIFICATE"]:
        set_fields["CGPA"] = 0.0
        set_fields["cgpa"] = 0.0
        set_fields["active_backlogs"] = 0
        set_fields["sgpa"] = None
        set_fields["current_semester"] = None
        set_fields["enrollment_number"] = None
        verified_fields.pop("CGPA", None)
        verified_fields.pop("cgpa", None)
        verified_fields.pop("active_backlogs", None)
        verified_fields.pop("sgpa", None)
        verified_fields.pop("current_semester", None)
        verified_fields.pop("enrollment_number", None)
        doc_summaries.pop("ug_marksheet", None)

    elif doc_type == "RESUME":
        set_fields["has_resume"] = False
        set_fields["resume_url"] = None
        set_fields["resume_filename"] = None
        set_fields["resume_id"] = None
        set_fields["skills"] = []
        set_fields["technical_skills"] = []
        set_fields["soft_skills"] = []
        set_fields["languages"] = []
        set_fields["coding_languages"] = []
        set_fields["spoken_languages"] = []
        set_fields["social_links"] = {}
        for plat in ["linkedin", "github", "leetcode", "hackerrank", "codeforces", "kaggle", "geeksforgeeks", "twitter", "portfolio"]:
            set_fields[f"{plat}_url"] = None
            verified_fields.pop(f"{plat}_url", None)
        verified_fields.pop("skills", None)
        verified_fields.pop("technical_skills", None)
        verified_fields.pop("soft_skills", None)
        verified_fields.pop("languages", None)
        verified_fields.pop("coding_languages", None)
        verified_fields.pop("spoken_languages", None)
        verified_fields.pop("social_links", None)
        doc_summaries.pop("resume", None)

    set_fields["verified_fields"] = verified_fields
    set_fields["documents"] = doc_summaries

    await students_collection.update_one(
        {"$or": [{"user_id": user_id}, {"student_id": user_id}, {"email": user_id}]},
        {"$set": set_fields}
    )

    return {
        "message": f"{doc_type or 'Document'} removed and verified profile data cleared successfully.",
        "document_id": document_id,
        "target_type": doc_type,
    }


def _format_field_dict(student_doc: dict, field_name: str, default_val: Any = None, active_doc_ids: Optional[set] = None) -> dict:
    prov = student_doc.get("verified_fields", {}).get(field_name) or {}
    source_doc_id = prov.get("source_document_id")

    # If the source document was deleted from verification_documents, treat field as unverified
    if active_doc_ids is not None and source_doc_id and source_doc_id not in active_doc_ids:
        prov = {}
        val = default_val
        is_verified = False
    else:
        val = student_doc.get(field_name, default_val)
        is_verified = field_name in student_doc.get("verified_fields", {})

    confidence = prov.get("confidence", 95.0) if is_verified else 0.0
    extraction_method = prov.get("extraction_method", "native")
    source = prov.get("source") or prov.get("source_document_type", "document")
    status_tier = "VERIFIED" if (is_verified and confidence >= 95.0) else ("REVIEW_REQUIRED" if (is_verified and confidence >= 80.0) else "SELF_REPORTED")
    return {
        "value": val,
        "confidence": round(float(confidence), 1),
        "extraction_method": extraction_method,
        "source": source,
        "is_verified": is_verified,
        "status": status_tier,
        "provenance": prov,
    }


@router.get("/profile/verification-state")
async def get_profile_verification_state(
    user_id: str = Depends(get_current_user_id),
):
    """
    Returns full verification state of the student profile with field provenance and editable boundaries.
    """
    user_doc = await users_collection.find_one({"$or": [{"user_id": user_id}, {"email": user_id}]})
    student_doc = await students_collection.find_one({
        "$or": [{"user_id": user_id}, {"student_id": user_id}, {"email": user_id}]
    })

    if not student_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student profile not found.")

    student_id = student_doc.get("student_id", user_id)
    active_docs = await verification_documents_collection.find({
        "$or": [{"student_id": student_id}, {"user_id": user_id}, {"user_id": student_id}]
    }).to_list(100)
    active_doc_ids = {d["document_id"] for d in active_docs}

    raw_docs_summary = student_doc.get("documents", {})
    cleaned_docs_summary = {k: v for k, v in raw_docs_summary.items() if v.get("document_id") in active_doc_ids}

    return {
        "user_editable_fields": {
            "full_name": student_doc.get("full_name") or (user_doc.get("full_name") if user_doc else "Student Candidate"),
            "email": student_doc.get("email") or (user_doc.get("email") if user_doc else ""),
            "university": student_doc.get("university", "GSFC University"),
        },
        "document_verified_fields": {
            "CGPA": _format_field_dict(student_doc, "CGPA", 0.0, active_doc_ids),
            "active_backlogs": _format_field_dict(student_doc, "active_backlogs", 0, active_doc_ids),
            "tenth_percentage": _format_field_dict(student_doc, "tenth_percentage", None, active_doc_ids),
            "twelfth_percentage": _format_field_dict(student_doc, "twelfth_percentage", None, active_doc_ids),
            "diploma_cgpa": _format_field_dict(student_doc, "diploma_cgpa", None, active_doc_ids),
            "skills": _format_field_dict(student_doc, "skills", [], active_doc_ids),
            "languages": _format_field_dict(student_doc, "languages", [], active_doc_ids),
            "current_semester": _format_field_dict(student_doc, "current_semester", None, active_doc_ids),
            "branch": _format_field_dict(student_doc, "branch", student_doc.get("education"), active_doc_ids),
            "enrollment_number": _format_field_dict(student_doc, "enrollment_number", None, active_doc_ids),
        },
        "documents_summary": cleaned_docs_summary,
    }


class FlagFieldRequest(BaseModel):
    reason: Optional[str] = None


class AdminOverrideRequest(BaseModel):
    new_value: Any
    notes: Optional[str] = None


profile_router = APIRouter(prefix="/profile/verified-data", tags=["Verified Profile Data"])


@profile_router.post("/{field_name}/flag")
@router.post("/profile/verified-data/{field_name}/flag")
async def flag_verified_field_for_review(
    field_name: str,
    payload: Optional[FlagFieldRequest] = None,
    user_id: str = Depends(get_current_user_id),
):
    """
    Section 6: Flag an OCR-verified field for manual review by an admin/placement officer.
    Creates a dispute ticket in support_tickets_collection.
    """
    student_doc = await students_collection.find_one({
        "$or": [{"user_id": user_id}, {"student_id": user_id}, {"email": user_id}]
    })
    if not student_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student profile not found.")

    student_id = student_doc.get("student_id", user_id)
    current_val = student_doc.get(field_name)
    reason_str = payload.reason if payload and payload.reason else "Student flagged verified field for manual review"

    ticket_id = f"TICK-{uuid.uuid4().hex[:8].upper()}"
    ticket_doc = {
        "ticket_id": ticket_id,
        "student_id": student_id,
        "user_id": user_id,
        "type": "FIELD_DISPUTE",
        "field_name": field_name,
        "current_value": current_val,
        "reason": reason_str,
        "status": "flagged",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "notes": f"Field '{field_name}' flagged by student with value: {current_val}",
    }
    await support_tickets_collection.insert_one(ticket_doc)

    # Mark field as REVIEW_REQUIRED
    ver_fields = student_doc.get("verified_fields", {})
    if field_name in ver_fields:
        ver_fields[field_name]["verification_status"] = "REVIEW_REQUIRED"
        ver_fields[field_name]["flagged"] = True
        await students_collection.update_one(
            {"_id": student_doc["_id"]},
            {"$set": {"verified_fields": ver_fields}}
        )

    return {
        "message": f"Field '{field_name}' successfully flagged for review.",
        "ticket_id": ticket_id,
        "status": "flagged",
    }


@profile_router.patch("/{field_name}/admin-override")
@router.patch("/profile/verified-data/{field_name}/admin-override")
async def admin_override_verified_field(
    field_name: str,
    payload: AdminOverrideRequest,
    student_id: Optional[str] = None,
    token_payload: dict = Depends(require_roles(["recruiter", "admin"])),
):
    """
    Section 6: Admin/Recruiter overrides an OCR-verified field with an authoritative value and note.
    Marked 'Manually Verified by Admin'.
    """
    user_id = token_payload["sub"]
    query = {"$or": [{"student_id": student_id}, {"user_id": student_id}]} if student_id else {"$or": [{"user_id": user_id}, {"student_id": user_id}]}
    student_doc = await students_collection.find_one(query)
    if not student_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student profile not found.")

    old_val = student_doc.get(field_name)
    now_iso = datetime.now(timezone.utc).isoformat()

    new_val = payload.new_value
    if field_name in ("CGPA", "tenth_percentage", "twelfth_percentage", "diploma_cgpa", "sgpa"):
        try:
            new_val = float(new_val)
        except (ValueError, TypeError):
            pass
    elif field_name in ("active_backlogs", "closed_backlogs", "tenth_passing_year", "twelfth_passing_year", "current_semester"):
        try:
            new_val = int(new_val)
        except (ValueError, TypeError):
            pass

    ver_fields = student_doc.get("verified_fields", {})
    ver_fields[field_name] = {
        "value": new_val,
        "confidence": 100.0,
        "extraction_method": "manual_override",
        "source": "Manually Verified by Admin",
        "verification_status": "VERIFIED",
        "reviewer_notes": payload.notes or "Admin override",
        "verified_at": now_iso,
        "overridden_by": user_id,
    }

    await students_collection.update_one(
        {"_id": student_doc["_id"]},
        {"$set": {
            field_name: new_val,
            "verified_fields": ver_fields,
        }}
    )

    # Log immutable audit entry
    audit_doc = {
        "audit_id": str(uuid.uuid4()),
        "student_id": student_doc.get("student_id", user_id),
        "field_name": field_name,
        "old_value": old_val,
        "new_value": new_val,
        "source_document_type": "ADMIN_OVERRIDE",
        "reason": payload.notes or "Admin Override",
        "status": "VERIFIED",
        "timestamp": datetime.now(timezone.utc),
    }
    await verification_audits_collection.insert_one(audit_doc)

    # Resolve open dispute ticket if any
    await support_tickets_collection.update_many(
        {"student_id": student_doc.get("student_id", user_id), "field_name": field_name, "status": "flagged"},
        {"$set": {"status": "resolved", "recruiter_response": payload.notes or "Overridden by admin"}}
    )

    return {
        "message": f"Field '{field_name}' successfully overridden by admin.",
        "field_name": field_name,
        "new_value": new_val,
        "source": "Manually Verified by Admin",
        "status": "VERIFIED",
    }


@profile_router.patch("")
@router.patch("/profile/verified-data")
async def update_self_reported_data(
    data: Dict[str, Any],
    user_id: str = Depends(get_current_user_id),
):
    """
    Section 5: Updates self-reported student data for fields below confidence threshold.
    """
    student_doc = await students_collection.find_one({
        "$or": [{"user_id": user_id}, {"student_id": user_id}, {"email": user_id}]
    })
    if not student_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student profile not found.")

    ver_fields = student_doc.get("verified_fields", {})
    allowed_self_reported = ("tenth_percentage", "twelfth_percentage", "diploma_cgpa", "skills", "languages", "branch")

    update_set = {}
    for k, v in data.items():
        if k in allowed_self_reported:
            if k in ver_fields and ver_fields[k].get("confidence", 0) >= 95.0 and ver_fields[k].get("verification_status") == "VERIFIED":
                continue
            update_set[k] = v

    if update_set:
        await students_collection.update_one(
            {"_id": student_doc["_id"]},
            {"$set": update_set}
        )

    return {
        "message": "Self-reported profile data updated.",
        "updated_fields": list(update_set.keys()),
    }


@router.post("/{document_id}/extract")
async def extract_document_by_id(
    document_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """
    Section 10: Re-triggers text extraction and verification on an already stored document.
    """
    doc = await verification_documents_collection.find_one({"document_id": document_id})
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found.")

    grid_file_id = doc.get("grid_file_id")
    if not grid_file_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No stored document file found.")

    try:
        from app.database import get_grid_fs
        grid_bucket = get_grid_fs()

        file_stream = io.BytesIO()
        await grid_bucket.download_to_stream(ObjectId(grid_file_id), file_stream)
        contents = file_stream.getvalue()

        from app.document_detection.extractor import extract_document_text
        from app.document_detection.classifier import classify_document

        res = await extract_document_text(contents, filename=doc.get("filename", "document.pdf"))
        classification = classify_document(res.text, filename=doc.get("filename", ""))

        return {
            "message": "Extraction complete.",
            "document_id": document_id,
            "detected_type": classification.document_type.value,
            "extraction_method": res.method,
            "extracted_character_count": len(res.text),
        }
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Extraction failed: {str(e)}")


@router.post("/{document_id}/review-action")
async def review_document_action(
    document_id: str,
    action: str = Form(...),  # approve or reject
    notes: Optional[str] = Form(None),
    token_payload: dict = Depends(require_roles(["recruiter", "admin"])),
):
    """
    Reviewer/Admin endpoint to approve or reject documents flagged for MANUAL_REVIEW.
    """
    user_id = token_payload["sub"]
    doc = await verification_documents_collection.find_one({"document_id": document_id})
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found.")

    if action.lower() == "approve":
        await verification_documents_collection.update_one(
            {"document_id": document_id},
            {"$set": {
                "processing_status": "VERIFIED",
                "reviewer_notes": notes,
                "verified_at": datetime.now(timezone.utc).isoformat(),
            }}
        )
        student_id = doc.get("student_id")
        student_doc = await students_collection.find_one({"student_id": student_id})
        if student_doc:
            await DocumentVerificationService._sync_verified_profile(
                student_doc=student_doc,
                student_id=student_id,
                document_id=document_id,
                doc_type=doc.get("document_type"),
                parsed_fields=doc.get("extracted_data", {}),
                clean_filename=doc.get("filename"),
                file_url=doc.get("file_url"),
                grid_file_id=doc.get("grid_file_id"),
                confidences={"ocr": 95.0, "extraction": 95.0, "validation": 95.0},
                extraction_method="manual_approval",
            )
        return {"message": "Document manually approved and profile synchronized.", "status": "VERIFIED"}
    else:
        await verification_documents_collection.update_one(
            {"document_id": document_id},
            {"$set": {
                "processing_status": "FAILED",
                "reviewer_notes": notes,
            }}
        )
        return {"message": "Document rejected by reviewer.", "status": "FAILED"}