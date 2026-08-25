"""
Document Classifier Engine.
Combines rule-based section detection, regex matchers, text statistics,
and disqualifier penalties to score and classify documents.
"""
import re
from typing import List, Tuple
from .schemas import DocumentClassificationResult, DocumentTypeEnum
from .rules import (
    RESUME_CONFIDENCE_THRESHOLD,
    EMAIL_REGEX,
    PHONE_REGEX,
    URL_REGEX,
    DATE_RANGE_REGEX,
    SECTION_RULES,
    ACTION_VERBS,
    NON_RESUME_DISQUALIFIERS,
)


def calculate_resume_score(text: str, filename: str = "") -> Tuple[float, List[str], List[str], List[str]]:
    """
    Computes numerical resume score, detected sections, matching reasons, and penalties.
    
    Returns:
        Tuple of (raw_score: float, detected_sections: List[str], reasons: List[str], penalties: List[str])
    """
    text_lower = text.lower()
    words = set(re.findall(r'\b[a-z]{2,}\b', text_lower))
    total_words = len(text.split())

    score = 0.0
    detected_sections: List[str] = []
    reasons: List[str] = []
    penalties: List[str] = []

    # 1. Contact Information (+20 pts max)
    contact_pts = 0.0
    if EMAIL_REGEX.search(text):
        contact_pts += 10.0
        reasons.append("Contains candidate email address (+10 pts)")
    if PHONE_REGEX.search(text):
        contact_pts += 5.0
        reasons.append("Contains candidate phone number (+5 pts)")
    if URL_REGEX.search(text):
        contact_pts += 5.0
        reasons.append("Contains professional URL link (LinkedIn/GitHub/Portfolio) (+5 pts)")
    
    contact_pts = min(20.0, contact_pts)
    if contact_pts > 0:
        score += contact_pts
        detected_sections.append("Contact Information")

    # 2. Education Section (+15 pts max)
    edu_keywords = SECTION_RULES["education"]["keywords"]
    matched_edu = [kw for kw in edu_keywords if kw in text_lower]
    if len(matched_edu) >= 2:
        score += 15.0
        detected_sections.append("Education")
        reasons.append(f"Education section detected (matched: {', '.join(matched_edu[:3])}) (+15 pts)")
    elif len(matched_edu) == 1:
        score += 8.0
        detected_sections.append("Education")
        reasons.append(f"Basic education keywords detected ({matched_edu[0]}) (+8 pts)")

    # 3. Work Experience & History (+20 pts max)
    exp_keywords = SECTION_RULES["experience"]["keywords"]
    matched_exp = [kw for kw in exp_keywords if kw in text_lower]
    has_date_range = bool(DATE_RANGE_REGEX.search(text))

    if len(matched_exp) >= 2 or (matched_exp and has_date_range):
        score += 20.0
        detected_sections.append("Work Experience")
        reasons.append(f"Work experience section detected (matched: {', '.join(matched_exp[:3])}) (+20 pts)")
    elif len(matched_exp) == 1:
        score += 10.0
        detected_sections.append("Work Experience")
        reasons.append(f"Basic experience keyword detected ({matched_exp[0]}) (+10 pts)")

    # 4. Technical & Professional Skills (+15 pts max)
    skills_keywords = SECTION_RULES["skills"]["keywords"]
    matched_skills = [kw for kw in skills_keywords if kw in text_lower]
    if len(matched_skills) >= 2:
        score += 15.0
        detected_sections.append("Skills")
        reasons.append(f"Technical skills section detected (matched: {', '.join(matched_skills[:3])}) (+15 pts)")
    elif len(matched_skills) == 1:
        score += 8.0
        detected_sections.append("Skills")
        reasons.append(f"Basic skills keyword detected ({matched_skills[0]}) (+8 pts)")

    # 5. Projects Section (+10 pts max)
    proj_keywords = SECTION_RULES["projects"]["keywords"]
    matched_proj = [kw for kw in proj_keywords if kw in text_lower]
    if len(matched_proj) >= 1:
        score += 10.0
        detected_sections.append("Projects")
        reasons.append(f"Projects section detected (matched: {', '.join(matched_proj[:2])}) (+10 pts)")

    # 6. Certifications & Honors (+5 pts max)
    cert_keywords = SECTION_RULES["certifications"]["keywords"]
    matched_cert = [kw for kw in cert_keywords if kw in text_lower]
    if len(matched_cert) >= 1:
        score += 5.0
        detected_sections.append("Certifications")
        reasons.append(f"Certifications / Awards detected ({matched_cert[0]}) (+5 pts)")

    # 7. Summary / Objective (+10 pts max)
    summary_keywords = SECTION_RULES["summary"]["keywords"]
    matched_summary = [kw for kw in summary_keywords if kw in text_lower]
    if len(matched_summary) >= 1:
        score += 10.0
        detected_sections.append("Summary / Objective")
        reasons.append(f"Professional summary / objective detected ({matched_summary[0]}) (+10 pts)")

    # 8. Resume Structural Cues (+5 pts max)
    action_verb_count = len(words.intersection(ACTION_VERBS))
    if action_verb_count >= 2 or "resume" in filename.lower() or "cv" in filename.lower():
        score += 5.0
        reasons.append("Resume action verbs or filename indicator present (+5 pts)")

    # 9. Non-Resume Disqualifier Penalties
    total_penalty = 0.0
    for disq_name, disq_data in NON_RESUME_DISQUALIFIERS.items():
        disq_kw = disq_data["keywords"]
        matches = [kw for kw in disq_kw if kw in text_lower]
        if len(matches) >= 2:
            penalty_val = disq_data["penalty"]
            total_penalty += penalty_val
            penalties.append(f"Matched non-resume indicator ({disq_name}: {', '.join(matches[:3])}) ({penalty_val} pts)")

    # Deduct penalties from raw score
    score = max(0.0, score + total_penalty)

    return score, list(set(detected_sections)), reasons, penalties


def classify_document(text: str, filename: str = "") -> DocumentClassificationResult:
    """
    Main document classification pipeline.
    Classifies text as RESUME, OTHER_DOCUMENT, or UNCERTAIN with confidence score.
    """
    if not text or not text.strip():
        return DocumentClassificationResult(
            document_type=DocumentTypeEnum.OTHER_DOCUMENT,
            confidence=0.0,
            is_resume=False,
            raw_score=0.0,
            detected_sections=[],
            reasons=["Document text is empty or unreadable."],
            error="No readable text extracted from file."
        )

    word_count = len(text.split())
    if word_count < 15:
        return DocumentClassificationResult(
            document_type=DocumentTypeEnum.OTHER_DOCUMENT,
            confidence=0.15,
            is_resume=False,
            raw_score=10.0,
            detected_sections=[],
            reasons=[f"Document text is too short ({word_count} words). Resumes require comprehensive content."],
            error="Text length insufficient for a valid resume."
        )

    raw_score, detected_sections, positive_reasons, penalty_reasons = calculate_resume_score(text, filename)

    # Normalize score to confidence (0.00 to 1.00)
    confidence = min(1.00, max(0.00, raw_score / 100.0))

    all_reasons = positive_reasons + penalty_reasons

    is_resume = confidence >= RESUME_CONFIDENCE_THRESHOLD

    if is_resume:
        doc_type = DocumentTypeEnum.RESUME
    elif confidence >= 0.40:
        doc_type = DocumentTypeEnum.UNCERTAIN
    else:
        doc_type = DocumentTypeEnum.OTHER_DOCUMENT

    return DocumentClassificationResult(
        document_type=doc_type,
        confidence=round(confidence, 2),
        is_resume=is_resume,
        raw_score=round(raw_score, 1),
        detected_sections=detected_sections,
        reasons=all_reasons,
        error=None if is_resume else f"Document classification confidence ({int(confidence * 100)}%) is below the {int(RESUME_CONFIDENCE_THRESHOLD * 100)}% threshold."
    )
