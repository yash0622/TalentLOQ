import io
import logging
from typing import Optional
from bson import ObjectId
from fastapi import APIRouter, HTTPException, status
from fastapi.responses import Response
from app.database import grid_fs, async_db

logger = logging.getLogger("talentloq.files")

router = APIRouter(tags=["Files"])

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
async def get_file_by_id(file_id: str):
    """
    Retrieve and stream binary file directly from MongoDB GridFS database bucket.
    """
    grid_out = await _fetch_gridfs_stream(file_id)

    if not grid_out:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"File '{file_id}' not found in MongoDB GridFS database."
        )

    content = await grid_out.read()
    metadata = getattr(grid_out, "metadata", {}) or {}
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
            "Cache-Control": "public, max-age=86400",
        }
    )

@router.get("/static/uploads/{filename}")
async def get_legacy_static_file(filename: str):
    """
    Backwards-compatibility route for legacy /static/uploads/... links.
    Streams directly from MongoDB GridFS without reading from local disk.
    """
    grid_out = await _fetch_gridfs_stream(filename)

    if not grid_out:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"File '{filename}' not found in MongoDB GridFS database."
        )

    content = await grid_out.read()
    metadata = getattr(grid_out, "metadata", {}) or {}
    content_type = metadata.get("content_type") or "application/pdf"

    return Response(
        content=content,
        media_type=content_type,
        headers={
            "Content-Disposition": f'inline; filename="{filename}"',
            "Cache-Control": "public, max-age=86400",
        }
    )
