"""
Document Type Detection & Verification Package for Talentloq.
"""
from .schemas import (
    DocumentTypeEnum,
    DocumentClassificationResult,
    VerificationStatusEnum,
    DocumentVerificationResult,
    ExtractedField,
)
from .rules import RESUME_CONFIDENCE_THRESHOLD
from .extractor import extract_document_text
from .classifier import classify_document, calculate_resume_score
from .parsers import (
    ResumeParser,
    TenthMarksheetParser,
    TwelfthDiplomaParser,
    UGMarksheetParser,
)
from .validator import DocumentValidator
from .image_preprocessor import ImageQualityPreprocessor, QualityCheckResult
from .service import DocumentVerificationService

__all__ = [
    "DocumentTypeEnum",
    "DocumentClassificationResult",
    "VerificationStatusEnum",
    "DocumentVerificationResult",
    "ExtractedField",
    "RESUME_CONFIDENCE_THRESHOLD",
    "extract_document_text",
    "classify_document",
    "calculate_resume_score",
    "ResumeParser",
    "TenthMarksheetParser",
    "TwelfthDiplomaParser",
    "UGMarksheetParser",
    "DocumentValidator",
    "ImageQualityPreprocessor",
    "QualityCheckResult",
    "DocumentVerificationService",
]