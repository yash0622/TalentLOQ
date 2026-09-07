from enum import Enum
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field

class DocumentTypeEnum(str, Enum):
    RESUME = "RESUME"
    TENTH_MARKSHEET = "TENTH_MARKSHEET"
    TWELFTH_MARKSHEET = "TWELFTH_MARKSHEET"
    DIPLOMA_MARKSHEET = "DIPLOMA_MARKSHEET"
    UG_MARKSHEET = "UG_MARKSHEET"
    OTHER_DOCUMENT = "OTHER_DOCUMENT"
    UNCERTAIN = "UNCERTAIN"

class VerificationStatusEnum(str, Enum):
    PROCESSING = "PROCESSING"
    VERIFIED = "VERIFIED"
    REVIEW_REQUIRED = "REVIEW_REQUIRED"
    MANUAL_REVIEW = "MANUAL_REVIEW"
    FAILED = "FAILED"
    REPLACED = "REPLACED"

class ExtractedField(BaseModel):
    value: Any
    confidence: float = Field(default=95.0, ge=0.0, le=100.0)
    extraction_method: str = "native"
    source: str = ""
    raw_text: Optional[str] = None
    ocr_confidence: float = Field(default=95.0, ge=0.0, le=100.0)
    extraction_confidence: float = Field(default=95.0, ge=0.0, le=100.0)
    validation_confidence: float = Field(default=95.0, ge=0.0, le=100.0)
    status: VerificationStatusEnum = VerificationStatusEnum.VERIFIED
    validation_notes: List[str] = Field(default_factory=list)

    def to_spec_dict(self) -> Dict[str, Any]:
        return {
            "value": self.value,
            "confidence": round(self.confidence, 1),
            "extraction_method": self.extraction_method,
            "source": self.source,
        }

class DocumentClassificationResult(BaseModel):
    document_type: DocumentTypeEnum = Field(..., description="Detected classification of the document")
    confidence: float = Field(..., description="Confidence score normalized between 0.0 and 1.0")
    is_resume: bool = Field(..., description="True if document meets or exceeds resume confidence threshold")
    raw_score: float = Field(..., description="Unnormalized numerical score computed from signals")
    detected_sections: List[str] = Field(default_factory=list, description="List of recognized resume/marksheet sections")
    reasons: List[str] = Field(default_factory=list, description="Explainable breakdown of scoring signals")
    error: Optional[str] = Field(None, description="Extraction or processing error if any occurred")

    def to_dict(self):
        return {
            "document_type": self.document_type.value,
            "confidence": round(self.confidence, 2),
            "is_resume": self.is_resume,
            "score": round(self.raw_score, 1),
            "detected_sections": self.detected_sections,
            "reasons": self.reasons,
            "error": self.error,
        }

class DocumentVerificationResult(BaseModel):
    document_id: str
    document_type: DocumentTypeEnum
    target_type: Optional[str] = None
    status: VerificationStatusEnum
    overall_confidence: float
    ocr_confidence: float
    extraction_confidence: float
    validation_confidence: float
    extracted_fields: Dict[str, Any] = Field(default_factory=dict)
    field_metadata: Dict[str, Any] = Field(default_factory=dict)
    validation_errors: List[str] = Field(default_factory=list)
    warnings: List[str] = Field(default_factory=list)
    classification: Optional[DocumentClassificationResult] = None
    provenance: Dict[str, Any] = Field(default_factory=dict)
