import os
import re
from pathlib import Path
from typing import Tuple
from fastapi import UploadFile, HTTPException, status

ALLOWED_MIME_TYPES = {
    "application/pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/msword",
    "text/plain",
    "application/octet-stream",
    "image/jpeg",
    "image/png",
}

ALLOWED_EXTENSIONS = {
    ".pdf",
    ".docx",
    ".doc",
    ".txt",
    ".jpg",
    ".jpeg",
    ".png",
}

MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024  # 5MB limit

def sanitize_filename(filename: str) -> str:
    """Sanitizes filename against path traversal and special characters."""
    if not filename:
        return "unnamed_file"
    name = Path(filename.replace("\\", "/")).name.replace("..", "").replace("\x00", "")
    clean = re.sub(r'[^a-zA-Z0-9._-]', '_', name)
    clean = re.sub(r'_{2,}', '_', clean)
    return clean or "safe_upload"

def validate_file_upload(file: UploadFile, contents: bytes) -> Tuple[str, str]:
    """
    Validates resume / document uploads:
    - MIME type whitelist
    - Extension whitelist
    - Max size (5MB)
    - Path traversal scan
    Returns tuple of (sanitized_filename, content_type).
    """
    # 1. Path traversal check & filename sanitization
    filename = file.filename or "upload"
    if ".." in filename or "/" in filename or "\\" in filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Path traversal attempt detected in filename"
        )
    
    clean_filename = sanitize_filename(filename)

    # 2. Extension validation
    ext = Path(clean_filename).suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid file extension '{ext}'. Allowed extensions: {', '.join(sorted(ALLOWED_EXTENSIONS))}"
        )

    # 3. MIME type validation
    content_type = (file.content_type or "").lower()
    if content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid MIME type '{content_type}'. Allowed MIME types: {', '.join(sorted(ALLOWED_MIME_TYPES))}"
        )

    # 4. Max file size enforcement (5MB)
    if len(contents) > MAX_FILE_SIZE_BYTES:
        size_mb = round(len(contents) / (1024 * 1024), 2)
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File size exceeds 5MB limit. Uploaded file is {size_mb}MB"
        )

    return clean_filename, content_type