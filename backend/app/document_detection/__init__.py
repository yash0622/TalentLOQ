"""
Document Type Detection Package for Talentloq.
"""
from .schemas import DocumentTypeEnum, DocumentClassificationResult
from .rules import RESUME_CONFIDENCE_THRESHOLD
from .extractor import extract_document_text
from .classifier import classify_document, calculate_resume_score

__all__ = [
    "DocumentTypeEnum",
    "DocumentClassificationResult",
    "RESUME_CONFIDENCE_THRESHOLD",
    "extract_document_text",
    "classify_document",
    "calculate_resume_score",
]
