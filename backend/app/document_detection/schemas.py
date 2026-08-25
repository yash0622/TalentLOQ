from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field

class DocumentTypeEnum(str, Enum):
    RESUME = "RESUME"
    OTHER_DOCUMENT = "OTHER_DOCUMENT"
    UNCERTAIN = "UNCERTAIN"

class DocumentClassificationResult(BaseModel):
    document_type: DocumentTypeEnum = Field(..., description="Detected classification of the document")
    confidence: float = Field(..., description="Confidence score normalized between 0.0 and 1.0")
    is_resume: bool = Field(..., description="True if document meets or exceeds resume confidence threshold")
    raw_score: float = Field(..., description="Unnormalized numerical score computed from signals")
    detected_sections: List[str] = Field(default_factory=list, description="List of recognized resume sections")
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
