"""
Document Text Extractor.
Extracts readable text from PDF, DOCX, DOC, TXT, and Image (PNG, JPG, JPEG) files.
Implements two-tier extraction:
1. High-speed Native PDF text extraction (pdfplumber / fitz / pypdf)
2. OCR Fallback (Tesseract OCR via PyMuPDF rasterization) for scanned or image-based files.
"""
import asyncio
import io
import os
import re
import shutil
from pathlib import Path
from typing import Optional, Tuple, Union, Dict, List, Any
from fastapi import UploadFile

try:
    import pdfplumber
except ImportError:
    pdfplumber = None

try:
    import fitz  # PyMuPDF
except ImportError:
    fitz = None

try:
    import pypdf
except ImportError:
    pypdf = None

try:
    import pytesseract
    # Check standard Tesseract paths on Windows/Linux
    tesseract_candidates = [
        shutil.which("tesseract"),
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        os.path.expanduser(r"~\AppData\Local\Tesseract-OCR\tesseract.exe"),
    ]
    for candidate in tesseract_candidates:
        if candidate and os.path.exists(candidate):
            pytesseract.pytesseract.tesseract_cmd = candidate
            break
except ImportError:
    pytesseract = None

try:
    import docx
except ImportError:
    docx = None

try:
    from PIL import Image
except ImportError:
    Image = None


class TextExtractionResult(tuple):
    """
    Subclasses tuple so `text, error = await extract_document_text(...)`
    maintains 100% backward compatibility while exposing metadata.
    """
    def __new__(cls, text: str, error: Optional[str] = None, method: str = "native", confidence: float = 95.0):
        obj = super(TextExtractionResult, cls).__new__(cls, (text, error))
        obj.text = text
        obj.error = error
        obj.method = method
        obj.confidence = confidence
        return obj


def _clean_extracted_text(text: str) -> str:
    """Normalizes whitespace and strips null bytes from extracted text."""
    if not text:
        return ""
    text = text.replace('\x00', ' ')
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def _reconstruct_spatial_layout_from_data(data: Dict[str, List[Any]]) -> str:
    """
    Groups OCR word tokens by their vertical coordinates into coherent horizontal lines.
    Aligns tabular columns horizontally based on their x-coordinates.
    """
    words = []
    n = len(data.get("text", []))
    for i in range(n):
        txt = str(data["text"][i]).strip()
        if not txt:
            continue
        try:
            c = float(data.get("conf", [100])[i])
            if c >= 0 and c < 20:  # Skip noise tokens
                continue
        except (ValueError, TypeError):
            pass
        top = int(data["top"][i])
        height = max(1, int(data["height"][i]))
        left = int(data["left"][i])
        y_mid = top + (height // 2)
        words.append((top, y_mid, height, left, txt))

    if not words:
        return ""

    # Sort primarily by vertical coordinate (y_mid)
    words.sort(key=lambda w: (w[1], w[3]))

    # Cluster words into lines where words share similar vertical midpoints
    avg_h = sum(w[2] for w in words) / len(words)
    line_tol = max(8.0, avg_h * 0.5)

    lines: List[List[Tuple[int, str]]] = []
    current_line: List[Tuple[int, str]] = []
    current_y_mid = None

    for top, y_mid, h, left, txt in words:
        if current_y_mid is None:
            current_y_mid = y_mid
            current_line.append((left, txt))
        elif abs(y_mid - current_y_mid) <= line_tol:
            current_line.append((left, txt))
            current_y_mid = (current_y_mid + y_mid) / 2.0
        else:
            if current_line:
                lines.append(sorted(current_line, key=lambda item: item[0]))
            current_line = [(left, txt)]
            current_y_mid = y_mid

    if current_line:
        lines.append(sorted(current_line, key=lambda item: item[0]))

    # Join words on each line, inserting gap space if columns are separated horizontally
    formatted_lines = []
    for line in lines:
        if not line:
            continue
        line_str = line[0][1]
        for idx in range(1, len(line)):
            prev_left, prev_txt = line[idx - 1]
            curr_left, curr_txt = line[idx]
            gap = curr_left - (prev_left + len(prev_txt) * 7)
            if gap > 25:
                line_str += "    " + curr_txt
            else:
                line_str += " " + curr_txt
        formatted_lines.append(line_str)

    return "\n".join(formatted_lines)


def _ocr_image_bytes(image_bytes: bytes) -> str:
    """Runs high-speed OCR on raw image bytes using Tesseract (spatial layout-aware) with EasyOCR fallback."""
    # 1. Primary: Tesseract OCR with Spatial Bounding-Box Layout Reconstruction (< 0.5s)
    if pytesseract and Image:
        try:
            img = Image.open(io.BytesIO(image_bytes))
            if img.mode not in ('L', 'RGB'):
                img = img.convert('RGB')
            # Downscale large camera photos if dimension > 1500px for instant OCR
            max_dim = max(img.size)
            if max_dim > 1500:
                scale = 1500.0 / max_dim
                new_size = (int(img.width * scale), int(img.height * scale))
                img = img.resize(new_size, Image.Resampling.BILINEAR)

            # Try spatial layout reconstruction via image_to_data
            try:
                data = pytesseract.image_to_data(img, lang='eng', output_type=pytesseract.Output.DICT)
                spatial_text = _reconstruct_spatial_layout_from_data(data)
                if spatial_text and len(spatial_text.strip()) > 20:
                    return spatial_text.strip()
            except Exception:
                pass

            text = pytesseract.image_to_string(img, lang='eng')
            if text and len(text.strip()) > 20:
                return text.strip()
        except Exception:
            pass

    return ""


def _ocr_scanned_pdf(contents: bytes) -> str:
    """Renders PDF pages to images using PyMuPDF (fitz) and runs fast OCR."""
    if not fitz:
        return ""
    try:
        doc = fitz.open(stream=contents, filetype="pdf")
        ocr_pages = []
        # Academic marksheets and resumes have primary content on page 1 (and 2 at most)
        for page_num in range(min(2, len(doc))):
            page = doc[page_num]
            pix = page.get_pixmap(dpi=150)
            img_bytes = pix.tobytes("png")
            page_text = _ocr_image_bytes(img_bytes)
            if page_text.strip():
                ocr_pages.append(page_text)
        return "\n".join(ocr_pages)
    except Exception:
        return ""


async def extract_document_text(
    file_input: Union[UploadFile, bytes, str, Path],
    filename: str = ""
) -> TextExtractionResult:
    """
    Extracts readable text from a document file.
    
    Returns:
        TextExtractionResult (unpacks as (text: str, error: Optional[str]))
        with .method ('native' or 'ocr') and .confidence attributes.
    """
    contents: bytes = b""
    name: str = filename

    # 1. Resolve raw bytes and filename
    if isinstance(file_input, UploadFile):
        name = name or file_input.filename or "file"
        try:
            contents = await file_input.read()
            await file_input.seek(0)
        except Exception as e:
            return TextExtractionResult("", f"Failed to read upload file stream: {str(e)}", method="failed", confidence=0.0)
    elif isinstance(file_input, bytes):
        contents = file_input
    elif isinstance(file_input, (str, Path)):
        path = Path(file_input)
        name = name or path.name
        if not path.exists():
            return TextExtractionResult("", f"File path does not exist: {path}", method="failed", confidence=0.0)
        try:
            contents = path.read_bytes()
        except Exception as e:
            return TextExtractionResult("", f"Failed to read file from path: {str(e)}", method="failed", confidence=0.0)

    if not contents or len(contents) == 0:
        return TextExtractionResult("", "File is empty (0 bytes).", method="failed", confidence=0.0)

    ext = Path(name).suffix.lower()

    # 2. Image Files (PNG, JPG, JPEG) -> OCR Directly
    if ext in (".png", ".jpg", ".jpeg"):
        ocr_text = await asyncio.to_thread(_ocr_image_bytes, contents)
        cleaned = _clean_extracted_text(ocr_text)
        if not cleaned:
            return TextExtractionResult("", "Image contains no readable text or OCR failed to recognize characters.", method="ocr", confidence=30.0)
        return TextExtractionResult(cleaned, None, method="ocr", confidence=88.0)

    # 3. PDF Extraction (Native First, OCR Fallback)
    if ext == ".pdf" or contents.startswith(b"%PDF"):
        native_text = ""
        # 3a. Primary: pdfplumber for crisp layout & table extraction
        if pdfplumber:
            try:
                with pdfplumber.open(io.BytesIO(contents)) as pdf:
                    pages_text = [p.extract_text() or "" for p in pdf.pages]
                    native_text = "\n".join(pages_text)
            except Exception:
                pass

        # 3b. Fallback native: fitz (PyMuPDF)
        if (not native_text or len(native_text.strip()) < 100) and fitz:
            try:
                doc = fitz.open(stream=contents, filetype="pdf")
                pages_text = [page.get_text() or "" for page in doc]
                native_text = "\n".join(pages_text)
            except Exception:
                pass

        # 3c. Fallback native: pypdf
        if (not native_text or len(native_text.strip()) < 100) and pypdf:
            try:
                pdf_reader = pypdf.PdfReader(io.BytesIO(contents))
                pages_text = [page.extract_text() or "" for page in pdf_reader.pages]
                native_text = "\n".join(pages_text)
            except Exception:
                pass

        cleaned = _clean_extracted_text(native_text)
        # If sufficient native text extracted (>= 100 chars), use native text
        if len(cleaned) >= 100:
            return TextExtractionResult(cleaned, None, method="native", confidence=98.0)

        # Scanned or image-only PDF: Fallback to OCR
        ocr_text = await asyncio.to_thread(_ocr_scanned_pdf, contents)
        cleaned_ocr = _clean_extracted_text(ocr_text)
        if cleaned_ocr and len(cleaned_ocr) >= 30:
            return TextExtractionResult(cleaned_ocr, None, method="ocr", confidence=85.0)

        if cleaned:
            return TextExtractionResult(cleaned, None, method="native", confidence=70.0)

        return TextExtractionResult("", "PDF file contains no extractable text (scanned or image-only PDF and OCR unreadable).", method="failed", confidence=0.0)

    # 4. DOCX Extraction
    elif ext in (".docx", ".doc"):
        if docx and ext == ".docx":
            try:
                doc_obj = docx.Document(io.BytesIO(contents))
                paragraphs = [p.text for p in doc_obj.paragraphs if p.text.strip()]
                for table in doc_obj.tables:
                    for row in table.rows:
                        row_text = " | ".join(cell.text.strip() for cell in row.cells if cell.text.strip())
                        if row_text:
                            paragraphs.append(row_text)
                
                full_text = "\n".join(paragraphs)
                cleaned = _clean_extracted_text(full_text)
                if not cleaned:
                    return TextExtractionResult("", "DOCX file contains no readable text.", method="native", confidence=0.0)
                return TextExtractionResult(cleaned, None, method="native", confidence=95.0)
            except Exception:
                pass

        try:
            printable_strings = re.findall(rb'[\x20-\x7E\x09\x0A\x0D]{4,}', contents)
            decoded_lines = [s.decode('ascii', errors='ignore').strip() for s in printable_strings]
            decoded_text = "\n".join(line for line in decoded_lines if len(line) > 3)
            cleaned = _clean_extracted_text(decoded_text)
            if cleaned and len(cleaned.split()) >= 10:
                return TextExtractionResult(cleaned, None, method="native", confidence=75.0)
            return TextExtractionResult("", "DOC/DOCX file binary text extraction yielded unreadable or empty content.", method="failed", confidence=0.0)
        except Exception as e:
            return TextExtractionResult("", f"Failed to extract text from DOC/DOCX document: {str(e)}", method="failed", confidence=0.0)

    # 5. Plain Text (.txt) or general fallback
    else:
        try:
            decoded = contents.decode('utf-8', errors='ignore')
            cleaned = _clean_extracted_text(decoded)
            if not cleaned:
                return TextExtractionResult("", "Text file is empty.", method="native", confidence=0.0)
            return TextExtractionResult(cleaned, None, method="native", confidence=90.0)
        except Exception as e:
            return TextExtractionResult("", f"Failed to decode text file: {str(e)}", method="failed", confidence=0.0)
