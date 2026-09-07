"""
Document Verification Pipeline Orchestrator.
Coordinates:
- SHA-256 Change Detection & Hash Caching
- Native Extraction with OCR Fallback
- Multi-Type Document Classification
- Field Extraction & Normalization
- Semantic Validation & Cross-Document Checks
- Direct Canonical Profile Synchronization (with zero blind overwrites)
- Immutable Audit Logging & Data Provenance
"""
import asyncio
import hashlib
import io
import logging
import uuid
from datetime import datetime, timezone
from typing import Dict, Any, Optional
from fastapi import UploadFile, HTTPException, status

logger = logging.getLogger(__name__)

from app.database import (
    async_db,
    grid_fs,
    students_collection,
    users_collection,
    verification_documents_collection,
    verification_audits_collection,
)
from app.upload_validator import validate_file_upload
from .schemas import (
    DocumentTypeEnum,
    VerificationStatusEnum,
    DocumentVerificationResult,
)
from .extractor import extract_document_text
from .classifier import classify_document
from .parsers import (
    ResumeParser,
    TenthMarksheetParser,
    TwelfthDiplomaParser,
    UGMarksheetParser,
)
from .marks_table_extractor import MarksTableExtractor
from .gemini_extractor import GeminiDocumentExtractor
from .validator import DocumentValidator
from .image_preprocessor import ImageQualityPreprocessor


def compute_sha256(data: bytes) -> str:
    """Computes SHA-256 fingerprint of file byte contents."""
    return hashlib.sha256(data).hexdigest()


class DocumentVerificationService:
    @classmethod
    async def process_document_upload(
        cls,
        file: UploadFile,
        user_id: str,
        target_type: Optional[str] = None,  # RESUME, TENTH_MARKSHEET, TWELFTH_OR_DIPLOMA, UG_MARKSHEET
    ) -> DocumentVerificationResult:
        """
        Executes the full end-to-end verification pipeline on an uploaded academic document.
        """
        contents = await file.read()
        clean_filename, content_type = validate_file_upload(file, contents)

        # 0. Pre-Flight Image Quality Gate & Non-Destructive Enhancer (OpenCV + Pillow)
        quality_check = await asyncio.to_thread(ImageQualityPreprocessor.check_quality, contents, filename=clean_filename)
        if quality_check.is_image and not quality_check.is_acceptable:
            logger.warning(
                "Upload rejected at pre-flight gate for user_id=%s, file=%s: %s",
                user_id,
                clean_filename,
                quality_check.rejection_reason,
            )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=quality_check.rejection_reason,
            )

        if quality_check.is_image:
            contents, opt_meta = await asyncio.to_thread(ImageQualityPreprocessor.preprocess_and_optimize, contents, filename=clean_filename)
            logger.debug("Image preprocessed: %s", opt_meta)

        file_hash = compute_sha256(contents)

        # 1. Fetch Student Profile for Cross-Validation (Self-healing from users if missing)
        student_doc = await students_collection.find_one({
            "$or": [{"user_id": user_id}, {"student_id": user_id}, {"email": user_id}]
        })
        if not student_doc:
            user_doc = await users_collection.find_one({"$or": [{"user_id": user_id}, {"email": user_id}]})
            if user_doc:
                new_student_id = str(uuid.uuid4())
                student_doc = {
                    "student_id": new_student_id,
                    "user_id": user_doc.get("user_id", user_id),
                    "full_name": user_doc.get("full_name", ""),
                    "university": "GSFC University",
                    "education": "BTech CSE",
                    "CGPA": 0.0,
                    "active_backlogs": 0,
                    "closed_backlogs": 0,
                    "skills": [],
                    "verified_fields": {},
                    "documents": {},
                }
                await students_collection.insert_one(student_doc)

        student_id = student_doc.get("student_id", user_id) if student_doc else user_id
        profile_name = student_doc.get("full_name") if student_doc else None
        profile_enrollment = student_doc.get("enrollment_number") if student_doc else None
        profile_university = student_doc.get("university") if student_doc else "GSFC University"

        # 2. Change Detection & Hash Caching (Only cache already VERIFIED documents)
        existing_doc = await verification_documents_collection.find_one({
            "student_id": student_id,
            "$or": [
                {"document_type": target_type},
                {"target_type": target_type}
            ],
            "file_hash": file_hash,
            "processing_status": "VERIFIED"
        })

        if existing_doc:
            # Ensure profile has synced fields even on cached hit
            if existing_doc.get("processing_status") == "VERIFIED" and student_doc:
                await cls._sync_verified_profile(
                    student_doc=student_doc,
                    student_id=student_id,
                    user_id=user_id,
                    document_id=existing_doc.get("document_id"),
                    doc_type=existing_doc.get("document_type"),
                    parsed_fields=existing_doc.get("extracted_data", {}),
                    clean_filename=existing_doc.get("filename", clean_filename),
                    file_url=existing_doc.get("file_url", ""),
                    grid_file_id=existing_doc.get("grid_file_id", ""),
                    confidences={
                        "ocr": existing_doc.get("ocr_confidence", 95.0),
                        "extraction": existing_doc.get("extraction_confidence", 95.0),
                        "validation": existing_doc.get("validation_confidence", 95.0),
                    },
                    extraction_method=existing_doc.get("extraction_method", "cached"),
                )

            # File is unchanged! Return cached verification without redundant OCR
            doc_type_enum = DocumentTypeEnum(existing_doc.get("document_type", "OTHER_DOCUMENT"))
            return DocumentVerificationResult(
                document_id=existing_doc.get("document_id"),
                document_type=doc_type_enum,
                target_type=target_type,
                status=VerificationStatusEnum(existing_doc.get("processing_status", "VERIFIED")),
                overall_confidence=existing_doc.get("validation_confidence", 95.0),
                ocr_confidence=existing_doc.get("ocr_confidence", 95.0),
                extraction_confidence=existing_doc.get("extraction_confidence", 95.0),
                validation_confidence=existing_doc.get("validation_confidence", 95.0),
                extracted_fields=existing_doc.get("extracted_data", {}),
                field_metadata={},
                validation_errors=[],
                warnings=["Unchanged document uploaded; reused cached verification."],
                provenance={
                    "cached": True,
                    "document_id": existing_doc.get("document_id"),
                    "file_hash": file_hash,
                }
            )

        # 3. Two-Tier Text Extraction (Native first, OCR fallback)
        extraction_res = await extract_document_text(contents, filename=clean_filename)
        extracted_text, extract_error = extraction_res.text, extraction_res.error
        extraction_method = getattr(extraction_res, "method", "native")
        base_ocr_conf = getattr(extraction_res, "confidence", 95.0)

        # 4. Document Classification
        classification = classify_document(extracted_text, filename=clean_filename, target_hint=target_type)
        detected_type = classification.document_type

        # Enforce slot target_type strictly (never allow a 10th marksheet to jump into 12th slot):
        if target_type == "TENTH_MARKSHEET":
            if detected_type != DocumentTypeEnum.RESUME:
                detected_type = DocumentTypeEnum.TENTH_MARKSHEET
        elif target_type in ("TWELFTH_OR_DIPLOMA", "TWELFTH_MARKSHEET", "DIPLOMA_MARKSHEET"):
            if detected_type != DocumentTypeEnum.RESUME:
                if "diploma" in extracted_text.lower() or "polytechnic" in extracted_text.lower():
                    detected_type = DocumentTypeEnum.DIPLOMA_MARKSHEET
                else:
                    detected_type = DocumentTypeEnum.TWELFTH_MARKSHEET
        elif target_type == "UG_MARKSHEET":
            if detected_type != DocumentTypeEnum.RESUME:
                detected_type = DocumentTypeEnum.UG_MARKSHEET
        elif target_type == "RESUME":
            detected_type = DocumentTypeEnum.RESUME

        # 5. Field Parsing per Document Type
        parsed_fields: Dict[str, Any] = {}
        if detected_type == DocumentTypeEnum.RESUME:
            # 1. Local baseline extraction
            local_parsed = ResumeParser.parse(extracted_text, profile_name=profile_name)
            parsed_fields = dict(local_parsed)

            # Fast-path check: If local heuristic extracted high density of skills & name, skip Gemini
            if len(parsed_fields.get("skills", [])) >= 8 and parsed_fields.get("student_name"):
                logger.info("Fast-path engaged for Resume: %d skills identified locally", len(parsed_fields["skills"]))
                extraction_method = "fastpath_ocr"
                base_ocr_conf = 98.0
            else:
                # 2. Try Gemini Flash AI Extraction
                ai_data = await asyncio.to_thread(
                    GeminiDocumentExtractor.extract_resume,
                    file_bytes=contents, filename=clean_filename, ocr_text=extracted_text
                )
                if ai_data:
                    extraction_method = "gemini_ai"
                    base_ocr_conf = 98.0
                    if ai_data.get("skills"):
                        merged_skills = set(parsed_fields.get("skills", [])).union(ai_data["skills"])
                        parsed_fields["skills"] = sorted(list(merged_skills))
                        parsed_fields["technical_skills"] = parsed_fields["skills"]

                    if ai_data.get("coding_languages"):
                        merged_coding = set(parsed_fields.get("coding_languages", [])).union(ai_data["coding_languages"])
                        parsed_fields["coding_languages"] = sorted(list(merged_coding))
                        parsed_fields["programming_languages"] = parsed_fields["coding_languages"]

                    if ai_data.get("spoken_languages"):
                        merged_spoken = set(parsed_fields.get("spoken_languages", [])).union(ai_data["spoken_languages"])
                        parsed_fields["spoken_languages"] = sorted(list(merged_spoken))
                        parsed_fields["languages"] = parsed_fields["spoken_languages"]

                    # Deployment skills
                    if ai_data.get("deployment_skills"):
                        merged_dep = set(parsed_fields.get("deployment_skills", [])).union(ai_data["deployment_skills"])
                        parsed_fields["deployment_skills"] = sorted(list(merged_dep))

                    # Internships & count
                    if ai_data.get("internships"):
                        ai_internships = ai_data["internships"]
                        local_internships = parsed_fields.get("internships", [])
                        # Prefer AI structured internships if found, otherwise keep local
                        parsed_fields["internships"] = ai_internships if ai_internships else local_internships
                    if "internship_count" in ai_data and ai_data["internship_count"] is not None:
                        parsed_fields["internship_count"] = max(int(ai_data["internship_count"]), len(parsed_fields.get("internships", [])))
                    else:
                        parsed_fields["internship_count"] = len(parsed_fields.get("internships", []))

                    # URIs: linkedin, github, leetcode, hackerrank, codeforces, kaggle, geeksforgeeks, twitter
                    ai_uris = ai_data.get("uris") or {}
                    social_links = dict(parsed_fields.get("social_links", {}))
                    for plat in ["linkedin", "github", "leetcode", "hackerrank", "codeforces", "kaggle", "geeksforgeeks", "twitter"]:
                        val = ai_uris.get(plat) or social_links.get(plat)
                        if val:
                            social_links[plat] = val
                            parsed_fields[f"{plat}_url"] = val
                    parsed_fields["social_links"] = social_links

        elif detected_type == DocumentTypeEnum.TENTH_MARKSHEET:
            local_parsed = TenthMarksheetParser.parse(extracted_text, profile_name=profile_name)
            # Fast-path check: If local parser extracted complete table and valid percentage
            if local_parsed.get("percentage") and local_parsed.get("total_subjects", 0) >= 4 and local_parsed.get("board"):
                logger.info("Fast-path engaged for 10th Marksheet: Percentage %s%% and %d subjects extracted locally", local_parsed["percentage"], local_parsed["total_subjects"])
                extraction_method = "fastpath_ocr"
                base_ocr_conf = 98.0
                parsed_fields = {
                    "student_name": local_parsed.get("student_name") or profile_name,
                    "board": local_parsed.get("board", "State Board"),
                    "passing_year": local_parsed.get("passing_year") or 2021,
                    "tenth_percentage": local_parsed.get("percentage"),
                    "total_marks_obtained": local_parsed.get("total_marks"),
                    "total_subjects": local_parsed.get("total_subjects"),
                    "subjects": local_parsed.get("subjects", []),
                    "marks_table_report": local_parsed.get("marks_report"),
                }
            else:
                ai_data = await asyncio.to_thread(
                    GeminiDocumentExtractor.extract_tenth_marksheet,
                    file_bytes=contents, filename=clean_filename, ocr_text=extracted_text
                )
                if ai_data and ai_data.get("percentage"):
                    extraction_method = "gemini_ai"
                    base_ocr_conf = 98.0
                    parsed_fields = {
                        "student_name": ai_data.get("student_name") or profile_name,
                        "board": ai_data.get("board", "State Board"),
                        "passing_year": ai_data.get("passing_year") or 2021,
                        "tenth_percentage": ai_data.get("percentage"),
                        "total_marks_obtained": ai_data.get("total_marks_obtained"),
                        "total_max_marks": ai_data.get("total_max_marks"),
                        "total_subjects": ai_data.get("total_subjects"),
                        "subjects": ai_data.get("subjects", []),
                    }
                    if ai_data.get("subjects"):
                        parsed_fields["marks_table_report"] = MarksTableExtractor._format_display_report(
                            "10th", ai_data["subjects"], ai_data["total_marks_obtained"], ai_data["total_max_marks"], ai_data["percentage"]
                        )
                else:
                    parsed_fields = local_parsed

        elif detected_type in (DocumentTypeEnum.TWELFTH_MARKSHEET, DocumentTypeEnum.DIPLOMA_MARKSHEET):
            local_parsed = TwelfthDiplomaParser.parse(extracted_text, profile_name=profile_name)
            is_local_diploma = local_parsed.get("document_subtype") == "DIPLOMA_MARKSHEET" or local_parsed.get("diploma_cgpa") is not None
            has_diploma_metrics = is_local_diploma and (local_parsed.get("diploma_cgpa") is not None or local_parsed.get("percentage") is not None)
            has_twelfth_metrics = not is_local_diploma and local_parsed.get("percentage") and local_parsed.get("total_subjects", 0) >= 4

            if has_diploma_metrics or has_twelfth_metrics:
                logger.info("Fast-path engaged for 12th/Diploma Marksheet locally")
                extraction_method = "fastpath_ocr"
                base_ocr_conf = 98.0
                if is_local_diploma:
                    detected_type = DocumentTypeEnum.DIPLOMA_MARKSHEET
                    parsed_fields = {
                        "student_name": local_parsed.get("student_name") or profile_name,
                        "diploma_cgpa": local_parsed.get("diploma_cgpa"),
                        "cgpa": local_parsed.get("diploma_cgpa"),
                        "college": local_parsed.get("board_or_university", "State Board of Technical Education"),
                        "passing_year": local_parsed.get("passing_year"),
                        "document_subtype": "DIPLOMA_MARKSHEET",
                    }
                else:
                    detected_type = DocumentTypeEnum.TWELFTH_MARKSHEET
                    parsed_fields = {
                        "student_name": local_parsed.get("student_name") or profile_name,
                        "board": local_parsed.get("board_or_university", "State Board"),
                        "passing_year": local_parsed.get("passing_year"),
                        "twelfth_percentage": local_parsed.get("percentage"),
                        "percentage": local_parsed.get("percentage"),
                        "total_subjects": local_parsed.get("total_subjects"),
                        "subjects": local_parsed.get("subjects", []),
                        "document_subtype": "TWELFTH_MARKSHEET",
                    }
            else:
                ai_data = await asyncio.to_thread(
                    GeminiDocumentExtractor.extract_twelfth_or_diploma,
                    file_bytes=contents, filename=clean_filename, ocr_text=extracted_text
                )
                if ai_data:
                    extraction_method = "gemini_ai"
                    base_ocr_conf = 98.0
                    sub_type = ai_data.get("document_subtype", "TWELFTH_MARKSHEET")
                    if sub_type == "DIPLOMA_MARKSHEET" or ai_data.get("diploma_cgpa") is not None:
                        detected_type = DocumentTypeEnum.DIPLOMA_MARKSHEET
                        parsed_fields = {
                            "student_name": ai_data.get("student_name") or profile_name,
                            "diploma_cgpa": ai_data.get("diploma_cgpa"),
                            "cgpa": ai_data.get("diploma_cgpa"),
                            "college": ai_data.get("board_or_college", "State Board of Technical Education"),
                            "passing_year": ai_data.get("passing_year"),
                            "document_subtype": "DIPLOMA_MARKSHEET",
                        }
                    else:
                        detected_type = DocumentTypeEnum.TWELFTH_MARKSHEET
                        parsed_fields = {
                            "student_name": ai_data.get("student_name") or profile_name,
                            "board": ai_data.get("board_or_college", "State Board"),
                            "passing_year": ai_data.get("passing_year"),
                            "twelfth_percentage": ai_data.get("percentage"),
                            "percentage": ai_data.get("percentage"),
                            "total_marks_obtained": ai_data.get("total_marks_obtained"),
                            "total_max_marks": ai_data.get("total_max_marks"),
                            "total_subjects": ai_data.get("total_subjects"),
                            "subjects": ai_data.get("subjects", []),
                            "document_subtype": "TWELFTH_MARKSHEET",
                        }
                        if ai_data.get("subjects"):
                            parsed_fields["marks_table_report"] = MarksTableExtractor._format_display_report(
                                "12th", ai_data["subjects"], ai_data["total_marks_obtained"], ai_data["total_max_marks"], ai_data["percentage"]
                            )
                else:
                    parsed_fields = local_parsed
                    if local_parsed.get("document_subtype") == "DIPLOMA_MARKSHEET":
                        detected_type = DocumentTypeEnum.DIPLOMA_MARKSHEET
                    else:
                        detected_type = DocumentTypeEnum.TWELFTH_MARKSHEET

        elif detected_type == DocumentTypeEnum.UG_MARKSHEET:
            local_parsed = UGMarksheetParser.parse(extracted_text, profile_name=profile_name)
            # Fast-path check: If CGPA, active backlogs, and enrollment number found locally
            if local_parsed.get("cgpa") is not None and local_parsed.get("active_backlogs") is not None and local_parsed.get("enrollment_number"):
                logger.info("Fast-path engaged for UG Marksheet: CGPA %s, Backlogs %s", local_parsed["cgpa"], local_parsed["active_backlogs"])
                extraction_method = "fastpath_ocr"
                base_ocr_conf = 98.0
                parsed_fields = dict(local_parsed)
            else:
                ai_data = await asyncio.to_thread(
                    GeminiDocumentExtractor.extract_ug_marksheet,
                    file_bytes=contents, filename=clean_filename, ocr_text=extracted_text
                )
                if ai_data and (ai_data.get("total_cgpa") is not None or ai_data.get("cgpa") is not None or ai_data.get("sgpa") is not None):
                    extraction_method = "gemini_ai"
                    base_ocr_conf = 98.0
                    effective_cgpa = ai_data.get("total_cgpa") if ai_data.get("total_cgpa") is not None else (ai_data.get("cgpa") if ai_data.get("cgpa") is not None else ai_data.get("sgpa"))
                    raw_backlogs = ai_data.get("current_backlogs") if ai_data.get("current_backlogs") is not None else ai_data.get("active_backlogs", 0)
                    enrollment = ai_data.get("enrollment_no") or ai_data.get("enrollment_number")
                    parsed_fields = {
                        "student_name": ai_data.get("student_name") or profile_name,
                        "university": ai_data.get("university") or profile_university,
                        "enrollment_number": enrollment,
                        "course": ai_data.get("course", "B.Tech"),
                        "branch": ai_data.get("branch", "Computer Science & Engineering"),
                        "current_semester": ai_data.get("current_semester"),
                        "sgpa": ai_data.get("sgpa"),
                        "cgpa": effective_cgpa,
                        "active_backlogs": raw_backlogs,
                    }
                else:
                    parsed_fields = local_parsed

        # 6. Semantic and Numeric Validation
        field_meta, val_errors, warnings, ocr_c, ext_c, val_c = DocumentValidator.validate_extracted_fields(
            detected_type.value,
            parsed_fields,
            extraction_method=extraction_method,
            base_ocr_conf=base_ocr_conf,
            source_filename=clean_filename,
        )

        # 7. Cross-Document Verification
        extracted_name = parsed_fields.get("student_name") or parsed_fields.get("candidate_name")
        extracted_enrollment = parsed_fields.get("enrollment_number")
        extracted_univ = parsed_fields.get("university")

        critical_mismatches, cross_warnings = DocumentValidator.perform_cross_document_validation(
            extracted_name=extracted_name,
            extracted_enrollment=extracted_enrollment,
            extracted_university=extracted_univ,
            profile_name=profile_name,
            profile_enrollment=profile_enrollment,
            profile_university=profile_university,
        )
        val_errors.extend(critical_mismatches)
        warnings.extend(cross_warnings)

        # 8. Decision Engine (VERIFIED, REVIEW_REQUIRED, MANUAL_REVIEW, FAILED)
        final_status = DocumentValidator.evaluate_verification_status(
            classification_confidence=classification.confidence,
            validation_conf=val_c,
            extraction_conf=ext_c,
            errors=val_errors,
            critical_mismatches=critical_mismatches,
        )

        if final_status in (VerificationStatusEnum.MANUAL_REVIEW, VerificationStatusEnum.REVIEW_REQUIRED):
            if not val_errors and not warnings:
                if ext_c < 40.0:
                    val_errors.append(f"Low parameter extraction confidence ({round(ext_c, 1)}%): Key fields were ambiguous or unreadable.")
                elif val_c < 70.0:
                    val_errors.append(f"Validation confidence was low ({round(val_c, 1)}%). Requires manual verification.")
                elif critical_mismatches:
                    val_errors.extend(critical_mismatches)
                else:
                    val_errors.append("Document requires coordinator review.")

        if not extracted_text:
            final_status = VerificationStatusEnum.FAILED
            val_errors.append("Document could not be read or decoded.")

        # 9. Store File in GridFS
        file_id_str = str(uuid.uuid4())[:8]
        safe_name = f"doc_{detected_type.value.lower()}_{file_id_str}_{clean_filename}"
        grid_file = await grid_fs.upload_from_stream(
            safe_name,
            io.BytesIO(contents),
            metadata={
                "filename": clean_filename,
                "content_type": content_type,
                "safe_name": safe_name,
                "file_hash": file_hash,
                "student_id": student_id,
                "document_type": detected_type.value,
                "uploaded_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        grid_file_id = str(grid_file)
        file_url = f"/api/v1/files/{grid_file_id}"
        document_id = str(uuid.uuid4())

        # 10. Record Document in MongoDB verification_documents collection
        doc_record = {
            "document_id": document_id,
            "student_id": student_id,
            "user_id": user_id,
            "document_type": detected_type.value,
            "target_type": target_type,
            "filename": clean_filename,
            "file_hash": file_hash,
            "grid_file_id": grid_file_id,
            "file_url": file_url,
            "processing_status": final_status.value,
            "extracted_data": parsed_fields,
            "ocr_confidence": round(ocr_c, 1),
            "extraction_confidence": round(ext_c, 1),
            "validation_confidence": round(val_c, 1),
            "validation_errors": val_errors,
            "warnings": warnings,
            "extraction_method": extraction_method,
            "uploaded_at": datetime.now(timezone.utc).isoformat(),
            "verified_at": datetime.now(timezone.utc).isoformat() if final_status == VerificationStatusEnum.VERIFIED else None,
        }
        await verification_documents_collection.insert_one(doc_record)

        # 11. Synchronize Canonical Student Profile ONLY IF VERIFIED
        if final_status == VerificationStatusEnum.VERIFIED and student_doc:
            await cls._sync_verified_profile(
                student_doc=student_doc,
                student_id=student_id,
                user_id=user_id,
                document_id=document_id,
                doc_type=detected_type.value,
                parsed_fields=parsed_fields,
                clean_filename=clean_filename,
                file_url=file_url,
                grid_file_id=grid_file_id,
                confidences={"ocr": ocr_c, "extraction": ext_c, "validation": val_c},
                extraction_method=extraction_method,
            )

        overall_conf = round((classification.confidence * 40.0 + (val_c * 0.4) + (ext_c * 0.2)), 1)

        return DocumentVerificationResult(
            document_id=document_id,
            document_type=detected_type,
            target_type=target_type,
            status=final_status,
            overall_confidence=overall_conf,
            ocr_confidence=round(ocr_c, 1),
            extraction_confidence=round(ext_c, 1),
            validation_confidence=round(val_c, 1),
            extracted_fields=parsed_fields,
            field_metadata={k: v.model_dump() for k, v in field_meta.items()},
            validation_errors=val_errors,
            warnings=warnings,
            classification=classification,
            provenance={
                "source_document_id": document_id,
                "source_document_type": detected_type.value,
                "extraction_method": extraction_method,
                "file_hash": file_hash,
                "file_url": file_url,
                "verified_at": datetime.now(timezone.utc).isoformat(),
            }
        )

    @classmethod
    async def _sync_verified_profile(
        cls,
        student_doc: Dict[str, Any],
        student_id: str,
        user_id: str,
        document_id: str,
        doc_type: str,
        parsed_fields: Dict[str, Any],
        clean_filename: str,
        file_url: str,
        grid_file_id: str,
        confidences: Dict[str, float],
        extraction_method: str,
    ):
        """
        Updates canonical fields in `students` collection and appends immutable audit records.
        """
        update_fields: Dict[str, Any] = {}
        provenance_updates: Dict[str, Any] = student_doc.get("verified_fields", {})
        now_iso = datetime.now(timezone.utc).isoformat()
        audit_records = []

        def apply_field(field_name: str, new_value: Any, reason: str = "Document Verified"):
            if new_value is not None:
                old_val = student_doc.get(field_name)
                update_fields[field_name] = new_value
                provenance_updates[field_name] = {
                    "value": new_value,
                    "confidence": confidences.get("validation", 95.0),
                    "extraction_method": extraction_method,
                    "source": clean_filename,
                    "source_document_id": document_id,
                    "source_document_type": doc_type,
                    "verification_status": "VERIFIED",
                    "verified_at": now_iso,
                }
                # Log audit entry
                audit_doc = {
                    "audit_id": str(uuid.uuid4()),
                    "student_id": student_id,
                    "field_name": field_name,
                    "old_value": old_val,
                    "new_value": new_value,
                    "source_document_id": document_id,
                    "source_document_type": doc_type,
                    "reason": reason,
                    "status": "VERIFIED",
                    "timestamp": datetime.now(timezone.utc),
                }
                audit_records.append(audit_doc)

        # Sync by Document Type
        if doc_type == "RESUME":
            skills = parsed_fields.get("skills")
            if skills:
                apply_field("skills", sorted(list(set(skills))), "Resume Skills Extraction")
            tech_skills = parsed_fields.get("technical_skills")
            if tech_skills:
                apply_field("technical_skills", sorted(list(set(tech_skills))), "Resume Technical Skills Extraction")
            soft_skills = parsed_fields.get("soft_skills")
            if soft_skills:
                apply_field("soft_skills", sorted(list(set(soft_skills))), "Resume Soft Skills Extraction")

            coding_langs = parsed_fields.get("coding_languages") or parsed_fields.get("programming_languages")
            if coding_langs:
                apply_field("coding_languages", sorted(list(set(coding_langs))), "Resume Coding Languages")

            spoken_langs = parsed_fields.get("spoken_languages") or parsed_fields.get("languages")
            if spoken_langs:
                apply_field("spoken_languages", sorted(list(set(spoken_langs))), "Resume Spoken Languages")
                apply_field("languages", sorted(list(set(spoken_langs))), "Resume Spoken Languages")

            # Deployment & DevOps Skills
            dep_skills = parsed_fields.get("deployment_skills") or []
            if dep_skills:
                apply_field("deployment_skills", sorted(list(set(dep_skills))), "Resume Deployment Skills")

            # Internships & Work Experience
            internships_list = parsed_fields.get("internships") or []
            internship_cnt = parsed_fields.get("internship_count", len(internships_list))
            apply_field("internships", internships_list, "Resume Internships")
            apply_field("internship_count", int(internship_cnt), "Resume Internships Count")

            # Platform & Coding Profile Links (clean overwrite so stale links are cleared if absent)
            social_links = parsed_fields.get("social_links") or {}
            update_fields["social_links"] = social_links

            for platform in ["linkedin", "github", "leetcode", "hackerrank", "codeforces", "kaggle", "geeksforgeeks", "twitter", "portfolio"]:
                field_key = f"{platform}_url"
                val = parsed_fields.get(field_key) or social_links.get(platform)
                update_fields[field_key] = val
                if val:
                    apply_field(field_key, val, f"Resume {platform.title()} Link")
                else:
                    provenance_updates.pop(field_key, None)

            # Canonical Resume fields
            update_fields["has_resume"] = True
            update_fields["resume_url"] = file_url
            update_fields["resume_id"] = grid_file_id
            update_fields["resume_filename"] = clean_filename
            update_fields["resume_uploaded_at"] = now_iso

        elif doc_type == "TENTH_MARKSHEET":
            apply_field("tenth_percentage", parsed_fields.get("tenth_percentage"), "10th Marksheet Verified")
            if parsed_fields.get("tenth_cgpa") is not None:
                apply_field("tenth_cgpa", parsed_fields.get("tenth_cgpa"), "10th Marksheet CGPA")
            apply_field("tenth_board", parsed_fields.get("board"), "10th Marksheet Board")
            apply_field("tenth_passing_year", parsed_fields.get("passing_year"), "10th Marksheet Year")

        elif doc_type == "TWELFTH_MARKSHEET":
            apply_field("twelfth_percentage", parsed_fields.get("twelfth_percentage") or parsed_fields.get("percentage"), "12th Marksheet Verified")
            apply_field("twelfth_board", parsed_fields.get("board") or parsed_fields.get("board_or_university"), "12th Board")
            apply_field("twelfth_passing_year", parsed_fields.get("passing_year"), "12th Year")
            # Clear previous diploma fields if replaced by 12th
            update_fields["diploma_cgpa"] = None
            update_fields["diploma_college"] = None
            provenance_updates.pop("diploma_cgpa", None)

        elif doc_type == "DIPLOMA_MARKSHEET":
            apply_field("diploma_cgpa", parsed_fields.get("diploma_cgpa") or parsed_fields.get("cgpa"), "Diploma CGPA Verified")
            apply_field("diploma_college", parsed_fields.get("college") or parsed_fields.get("board_or_university"), "Diploma Technical Board")
            # Clear previous 12th fields if replaced by diploma
            update_fields["twelfth_percentage"] = None
            update_fields["twelfth_board"] = None
            update_fields["twelfth_passing_year"] = None
            provenance_updates.pop("twelfth_percentage", None)

        elif doc_type == "UG_MARKSHEET":
            # Canonical CGPA field: use cgpa or fallback to sgpa
            cgpa_val = parsed_fields.get("cgpa") or parsed_fields.get("sgpa")
            if cgpa_val is not None:
                apply_field("CGPA", float(cgpa_val), "UG Marksheet Cumulative CGPA")
                apply_field("cgpa", float(cgpa_val), "UG Marksheet Cumulative CGPA")

            # Canonical active_backlogs field (only if numeric)
            backlog_val = parsed_fields.get("active_backlogs")
            if isinstance(backlog_val, int):
                apply_field("active_backlogs", backlog_val, "UG Marksheet Active Backlogs")

            apply_field("sgpa", parsed_fields.get("sgpa") or cgpa_val, "UG Marksheet SGPA")
            apply_field("current_semester", parsed_fields.get("current_semester"), "UG Current Semester")
            apply_field("branch", parsed_fields.get("branch"), "UG Branch")
            apply_field("enrollment_number", parsed_fields.get("enrollment_number"), "UG Enrollment No")

        # Category summary map
        category_map = {
            "RESUME": "resume",
            "TENTH_MARKSHEET": "tenth",
            "TWELFTH_MARKSHEET": "twelfth_diploma",
            "DIPLOMA_MARKSHEET": "twelfth_diploma",
            "UG_MARKSHEET": "ug_marksheet",
        }
        category_key = category_map.get(doc_type, "other")
        doc_summaries = student_doc.get("documents", {})
        doc_summaries[category_key] = {
            "document_id": document_id,
            "document_type": doc_type,
            "filename": clean_filename,
            "file_url": file_url,
            "status": "VERIFIED",
            "verified_at": now_iso,
        }
        update_fields["documents"] = doc_summaries
        update_fields["verified_fields"] = provenance_updates

        if update_fields:
            await students_collection.update_one(
                {"$or": [{"student_id": student_id}, {"user_id": user_id}]},
                {"$set": update_fields}
            )

        if audit_records:
            await verification_audits_collection.insert_many(audit_records)
