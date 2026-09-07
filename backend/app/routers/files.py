import io
import re
import logging
from typing import Optional, Any
from bson import ObjectId
from fastapi import APIRouter, HTTPException, Depends, status
from fastapi.responses import Response
from app.database import (
    grid_fs,
    async_db,
    verification_documents_collection,
    students_collection,
    drives_collection,
)
from app.dependencies import get_current_user

logger = logging.getLogger("talentloq.files")

router = APIRouter(tags=["Files"])

async def _verify_file_access(user_payload: dict, metadata: dict, grid_out: Any, file_identifier: str) -> None:
    user_role = user_payload.get("role", "student")
    user_id = str(user_payload.get("sub", ""))

    if user_role in ("recruiter", "admin"):
        return

    # Check direct ownership from metadata
    meta_owner = str(metadata.get("user_id") or metadata.get("student_id") or "")
    if meta_owner and meta_owner == user_id:
        return

    # Check verification_documents collection
    grid_id_str = str(getattr(grid_out, "_id", ""))
    filename = str(getattr(grid_out, "filename", file_identifier))
    doc = await verification_documents_collection.find_one({
        "$and": [
            {"$or": [{"user_id": user_id}, {"student_id": user_id}]},
            {"$or": [
                {"grid_file_id": grid_id_str},
                {"grid_file_id": file_identifier},
                {"filename": filename},
                {"filename": file_identifier},
            ]}
        ]
    })
    if doc:
        return

    # Check student profile documents
    student = await students_collection.find_one({
        "$or": [{"user_id": user_id}, {"student_id": user_id}]
    })
    if student:
        student_docs_str = str(student.get("documents", {}))
        if file_identifier in student_docs_str or grid_id_str in student_docs_str or filename in str(student.get("resume_url", "")) or filename in str(student.get("resume_filename", "")):
            return

    # Allow public drive attachments posted for students
    drive = await drives_collection.find_one({
        "$or": [
            {"attachment_pdf_url": {"$regex": re.escape(file_identifier)}},
            {"attachment_pdf_url": {"$regex": re.escape(filename)}},
        ]
    })
    if drive:
        return

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Access forbidden. You do not have permission to view this file."
    )

async def _fetch_gridfs_stream(file_identifier: str):
    """Utility to locate and open GridFS download stream by ObjectId or filename."""
    import motor.motor_asyncio
    grid_bucket = motor.motor_asyncio.AsyncIOMotorGridFSBucket(async_db)

    # 1. Try finding by ObjectId
    if ObjectId.is_valid(file_identifier):
        try:
            return await grid_bucket.open_download_stream(ObjectId(file_identifier))
        except Exception:
            pass

    # 2. Try finding by name directly in GridFS
    try:
        return await grid_bucket.open_download_stream_by_name(file_identifier)
    except Exception:
        pass

    # 3. Search fs.files for metadata match
    try:
        file_doc = await async_db["fs.files"].find_one({
            "$or": [
                {"filename": file_identifier},
                {"metadata.filename": file_identifier},
                {"metadata.safe_name": file_identifier},
                {"metadata.resume_id": file_identifier},
            ]
        })
        if file_doc:
            return await grid_bucket.open_download_stream(file_doc["_id"])
    except Exception:
        pass

    # 4. Local disk static/uploads fallback & auto-migration into GridFS
    try:
        from pathlib import Path
        clean_name = file_identifier.split("/")[-1].split("\\")[-1]
        local_path = Path("static/uploads") / clean_name
        if local_path.exists() and local_path.is_file():
            content = local_path.read_bytes()
            content_type = "application/pdf" if clean_name.lower().endswith(".pdf") else "application/octet-stream"
            file_id = await grid_bucket.upload_from_stream(
                clean_name,
                io.BytesIO(content),
                metadata={
                    "filename": clean_name,
                    "content_type": content_type,
                    "safe_name": clean_name,
                    "auto_migrated": True,
                }
            )
            return await grid_bucket.open_download_stream(file_id)
    except Exception:
        pass

    return None

@router.get("/api/v1/files/{file_id}")
async def get_file_by_id(
    file_id: str,
    user_payload: dict = Depends(get_current_user),
):
    """
    Retrieve and stream binary file directly from MongoDB GridFS database bucket.
    Protected endpoint: Requires valid authenticated session (student or recruiter).
    """
    grid_out = await _fetch_gridfs_stream(file_id)

    if not grid_out:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"File '{file_id}' not found in MongoDB GridFS database."
        )

    content = await grid_out.read()
    metadata = getattr(grid_out, "metadata", {}) or {}
    await _verify_file_access(user_payload, metadata, grid_out, file_id)
    content_type = metadata.get("content_type")
    filename = getattr(grid_out, "filename", "document.pdf") or "document.pdf"

    if not content_type:
        if filename.lower().endswith(".pdf"):
            content_type = "application/pdf"
        elif filename.lower().endswith((".png", ".jpg", ".jpeg")):
            ext = filename.split(".")[-1].lower()
            content_type = f"image/{'jpeg' if ext == 'jpg' else ext}"
        else:
            content_type = "application/octet-stream"

    return Response(
        content=content,
        media_type=content_type,
        headers={
            "Content-Disposition": f'inline; filename="{filename}"',
            "Cache-Control": "private, max-age=3600",
        }
    )

@router.get("/static/uploads/{filename}")
async def get_legacy_static_file(
    filename: str,
    user_payload: dict = Depends(get_current_user),
):
    """Backwards-compatibility route for legacy /static/uploads/... links."""
    return await get_file_by_id(file_id=filename, user_payload=user_payload)
