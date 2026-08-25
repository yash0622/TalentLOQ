"""
Document Text Extractor.
Extracts readable text from PDF, DOCX, DOC, and TXT files.
Handles corrupted, empty, or unreadable files gracefully.
"""
import io
import re
from pathlib import Path
from typing import Optional, Tuple, Union
from fastapi import UploadFile

try:
    import pypdf
except ImportError:
    pypdf = None

try:
    import docx
except ImportError:
    docx = None


def _clean_extracted_text(text: str) -> str:
    """Normalizes whitespace and strips null bytes from extracted text."""
    if not text:
        return ""
    # Strip null bytes & control chars
    text = text.replace('\x00', ' ')
    # Normalize multiple newlines/spaces
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


async def extract_document_text(
    file_input: Union[UploadFile, bytes, str, Path],
    filename: str = ""
) -> Tuple[str, Optional[str]]:
    """
    Extracts readable text from a document file.
    
    Returns:
        Tuple of (extracted_text: str, error_message: Optional[str])
    """
    contents: bytes = b""
    name: str = filename

    # 1. Resolve raw bytes and filename
    if isinstance(file_input, UploadFile):
        name = name or file_input.filename or "file"
        try:
            # Read fromUploadFile stream
            contents = await file_input.read()
            # Reset seek position for downstream usage
            await file_input.seek(0)
        except Exception as e:
            return "", f"Failed to read upload file stream: {str(e)}"
    elif isinstance(file_input, bytes):
        contents = file_input
    elif isinstance(file_input, (str, Path)):
        path = Path(file_input)
        name = name or path.name
        if not path.exists():
            return "", f"File path does not exist: {path}"
        try:
            contents = path.read_bytes()
        except Exception as e:
            return "", f"Failed to read file from path: {str(e)}"

    if not contents or len(contents) == 0:
        return "", "File is empty (0 bytes)."

    ext = Path(name).suffix.lower()

    # 2. Extract based on file extension / content
    # PDF Extraction
    if ext == ".pdf" or contents.startswith(b"%PDF"):
        if not pypdf:
            return "", "PDF extractor library (pypdf) is not available."
        try:
            pdf_reader = pypdf.PdfReader(io.BytesIO(contents))
            if pdf_reader.is_encrypted:
                try:
                    # Attempt empty password decrypt
                    pdf_reader.decrypt('')
                except Exception:
                    return "", "PDF file is password protected or encrypted."

            extracted_pages = []
            for page_num, page in enumerate(pdf_reader.pages):
                try:
                    page_text = page.extract_text() or ""
                    if page_text.strip():
                        extracted_pages.append(page_text)
                except Exception:
                    continue

            full_text = "\n".join(extracted_pages)
            cleaned = _clean_extracted_text(full_text)
            if not cleaned:
                return "", "PDF file contains no extractable text (scanned or image-only PDF)."
            return cleaned, None
        except Exception as e:
            return "", f"Corrupted or invalid PDF file: {str(e)}"

    # DOCX Extraction
    elif ext in (".docx", ".doc"):
        if docx and ext == ".docx":
            try:
                doc_obj = docx.Document(io.BytesIO(contents))
                paragraphs = [p.text for p in doc_obj.paragraphs if p.text.strip()]
                # Also extract text from tables
                for table in doc_obj.tables:
                    for row in table.rows:
                        row_text = " | ".join(cell.text.strip() for cell in row.cells if cell.text.strip())
                        if row_text:
                            paragraphs.append(row_text)
                
                full_text = "\n".join(paragraphs)
                cleaned = _clean_extracted_text(full_text)
                if not cleaned:
                    return "", "DOCX file contains no readable text."
                return cleaned, None
            except Exception as e:
                # Fallback to plain text stream scanning below
                pass

        # Fallback binary string extractor for .doc or corrupted docx
        try:
            # Extract printable ASCII/UTF-8 strings from binary stream
            printable_strings = re.findall(rb'[\x20-\x7E\x09\x0A\x0D]{4,}', contents)
            decoded_lines = [s.decode('ascii', errors='ignore').strip() for s in printable_strings]
            decoded_text = "\n".join(line for line in decoded_lines if len(line) > 3)
            cleaned = _clean_extracted_text(decoded_text)
            if cleaned and len(cleaned.split()) >= 10:
                return cleaned, None
            return "", "DOC/DOCX file binary text extraction yielded unreadable or empty content."
        except Exception as e:
            return "", f"Failed to extract text from DOC/DOCX document: {str(e)}"

    # Plain Text (.txt) or general fallback
    else:
        try:
            decoded = contents.decode('utf-8', errors='ignore')
            cleaned = _clean_extracted_text(decoded)
            if not cleaned:
                return "", "Text file is empty."
            return cleaned, None
        except Exception as e:
            return "", f"Failed to decode text file: {str(e)}"
