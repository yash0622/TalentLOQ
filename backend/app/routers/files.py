import io
import re
import logging
from pathlib import Path
from typing import Optional, Any
from bson import ObjectId
from fastapi import APIRouter, HTTPException, Depends, status, Query, BackgroundTasks
from fastapi.responses import Response
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.database import (
    grid_fs,
    async_db,
    verification_documents_collection,
    students_collection,
    drives_collection,
    company_listings_collection,
)
from app.jwt_utils import decode_token, create_download_token

logger = logging.getLogger("talentloq.files")

router = APIRouter(tags=["Files"])

file_security_bearer = HTTPBearer(auto_error=False)

async def get_file_user(
    token: Optional[str] = Query(None),
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(file_security_bearer),
) -> dict:
    """
    Authenticate file requests:
    - Normal Bearer header: accepts standard access tokens.
    - ?token= query parameter: accepts ONLY short-lived scoped download tokens (scope="file_download").
    """
    if credentials and credentials.credentials:
        payload = decode_token(credentials.credentials, expected_type="access")
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token claims.",
            )
        return payload

    if token:
        payload = decode_token(token.strip(), expected_type="download")
        if payload.get("scope") != "file_download":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Invalid token scope. Query parameter accepts only file download tokens.",
            )
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token claims.",
            )
        return payload

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Authentication token required via Bearer header or ?token= download token.",
    )

@router.get("/api/v1/files/token")
async def issue_file_download_token(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(file_security_bearer),
):
    """
    Issue a short-lived (5 min) download token for file viewing/download in browser tabs.
    Requires normal Bearer authentication.
    """
    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Bearer authentication required to obtain a download token.",
        )
    payload = decode_token(credentials.credentials, expected_type="access")
    user_id = payload.get("sub")
    role = payload.get("role", "student")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token claims.",
        )
    d_token = create_download_token(user_id=user_id, role=role)
    return {"download_token": d_token, "expires_in": 300}

async def _verify_file_access(user_payload: dict, metadata: dict, grid_out: Any, file_identifier: str) -> None:
    user_role = user_payload.get("role", "student")
    user_id = str(user_payload.get("sub", ""))

    if user_role in ("recruiter", "admin"):
        return

    # Check direct ownership from metadata
    meta_owner = str(metadata.get("user_id") or metadata.get("student_id") or "")
    if meta_owner and meta_owner == user_id:
        return

    # Check if file is marked public or is a drive brochure
    if metadata.get("is_public") or metadata.get("drive_id") or metadata.get("generated_by") == "TalentLOQ_Seeder":
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
            {"grid_file_id": file_identifier},
            {"attachment_pdf_url": {"$regex": re.escape(file_identifier)}},
            {"attachment_pdf_url": {"$regex": re.escape(filename)}},
        ]
    })
    if drive:
        return

    listing = await company_listings_collection.find_one({
        "$or": [
            {"pdf_url": {"$regex": re.escape(file_identifier)}},
            {"pdf_url": {"$regex": re.escape(filename)}},
        ]
    })
    if listing:
        return

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Access forbidden. You do not have permission to view this file."
    )

class LocalFileStream:
    """Wraps a local static file to provide the same async read interface as GridFS download stream."""
    def __init__(self, path: Path, filename: str):
        self.path = path
        self.filename = filename
        self._id = None
        ext = filename.split(".")[-1].lower() if "." in filename else ""
        content_type = (
            "application/pdf"
            if ext == "pdf"
            else (f"image/{'jpeg' if ext == 'jpg' else ext}" if ext in ("png", "jpg", "jpeg", "webp") else "application/octet-stream")
        )
        self.metadata = {
            "filename": filename,
            "content_type": content_type,
            "safe_name": filename,
        }

    async def read(self) -> bytes:
        return self.path.read_bytes()

async def migrate_legacy_file_to_gridfs(clean_name: str, local_path: Path) -> None:
    """Idempotently migrate a legacy disk upload to GridFS in the background."""
    try:
        existing = await async_db["fs.files"].find_one({
            "$or": [{"filename": clean_name}, {"metadata.filename": clean_name}]
        })
        if existing:
            return
        import motor.motor_asyncio
        grid_bucket = motor.motor_asyncio.AsyncIOMotorGridFSBucket(async_db)
        content = local_path.read_bytes()
        content_type = "application/pdf" if clean_name.lower().endswith(".pdf") else "application/octet-stream"
        await grid_bucket.upload_from_stream(
            clean_name,
            io.BytesIO(content),
            metadata={
                "filename": clean_name,
                "content_type": content_type,
                "safe_name": clean_name,
                "auto_migrated": True,
            },
        )
        logger.info(f"Successfully migrated legacy file '{clean_name}' to GridFS.")
    except Exception as e:
        logger.warning(f"Background legacy file migration failed for '{clean_name}': {e}")

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

    # 3.5 Search verification_documents collection for document_id match
    try:
        doc = await verification_documents_collection.find_one({"document_id": file_identifier})
        if doc and doc.get("grid_file_id"):
            grid_file_id = doc["grid_file_id"]
            if ObjectId.is_valid(grid_file_id):
                return await grid_bucket.open_download_stream(ObjectId(grid_file_id))
    except Exception:
        pass

    # 4. Local disk static/uploads fallback without writing in the GET/read path
    try:
        clean_name = file_identifier.split("/")[-1].split("\\")[-1]
        local_path = Path("static/uploads") / clean_name
        if local_path.exists() and local_path.is_file():
            return LocalFileStream(local_path, clean_name)
    except Exception:
        pass

    return None

@router.get("/api/v1/files/document/{document_id}")
async def get_file_by_document_id(
    document_id: str,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_file_user),
):
    """
    Retrieve and stream file associated with a verification document ID.
    Supports in-browser viewing (?token=) and Bearer auth.
    """
    doc = await verification_documents_collection.find_one({"document_id": document_id})
    if not doc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Document with ID '{document_id}' not found.",
        )
    file_id = doc.get("grid_file_id") or doc.get("filename")
    if not file_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No file stream attached to document '{document_id}'.",
        )
    return await get_file_by_id(file_id=str(file_id), background_tasks=background_tasks, user_payload=user_payload)

@router.get("/api/v1/files/{file_id}")
async def get_file_by_id(
    file_id: str,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_file_user),
):
    """
    Retrieve and stream binary file directly from MongoDB GridFS database bucket.
    Protected endpoint: Requires valid authenticated session (student or recruiter)
    via Authorization Bearer header or ?token= query parameter for browser tabs.
    """
    grid_out = await _fetch_gridfs_stream(file_id)

    if not grid_out:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"File '{file_id}' not found in MongoDB GridFS database."
        )

    if isinstance(grid_out, LocalFileStream) and background_tasks:
        background_tasks.add_task(migrate_legacy_file_to_gridfs, grid_out.filename, grid_out.path)

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

    # Sanitize filename to prevent header injection, CRLF splitting, or attribute alteration
    safe_filename = re.sub(r'[\r\n"\\/;\x00-\x1f\x7f-\x9f]', '_', filename).strip() or "document.pdf"

    return Response(
        content=content,
        media_type=content_type,
        headers={
            "Content-Disposition": f'inline; filename="{safe_filename}"',
            "Cache-Control": "private, max-age=3600",
        }
    )

@router.get("/static/uploads/{filename}")
async def get_legacy_static_file(
    filename: str,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_file_user),
):
    """Backwards-compatibility route for legacy /static/uploads/... links."""
    return await get_file_by_id(file_id=filename, background_tasks=background_tasks, user_payload=user_payload)
