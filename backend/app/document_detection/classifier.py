"""
Document Classifier Engine.
Combines rule-based section detection, regex matchers, text statistics,
and disqualifier penalties to score and classify documents.
"""
import re
from typing import List, Tuple, Optional
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
    TENTH_MARKSHEET_KEYWORDS,
    TWELFTH_MARKSHEET_KEYWORDS,
    DIPLOMA_MARKSHEET_KEYWORDS,
    UG_MARKSHEET_KEYWORDS,
)


def calculate_resume_score(text: str, filename: str = "") -> Tuple[float, List[str], List[str], List[str]]:
    """
    Computes numerical resume score, detected sections, matching reasons, and penalties.
    """
    text_lower = text.lower()
    words = set(re.findall(r'\b[a-z]{2,}\b', text_lower))

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

    score = max(0.0, score + total_penalty)
    return score, list(set(detected_sections)), reasons, penalties


def calculate_tenth_score(text: str, filename: str = "") -> Tuple[float, List[str]]:
    text_lower = text.lower()
    score = 0.0
    reasons = []

    # Disqualify if it has resume/assignment sections
    if any(k in text_lower for k in ["work experience", "career objective", "professional summary", "projects", "technical skills"]):
        return 0.0, ["Contains resume sections (not a marksheet)"]
    if any(k in text_lower for k in ["assignment", "homework", "syllabus", "question 1", "invoice"]):
        return 0.0, ["Contains assignment/invoice indicators"]

    matches = [kw for kw in TENTH_MARKSHEET_KEYWORDS if kw in text_lower]
    if matches:
        score += min(50.0, len(matches) * 20.0)
        reasons.append(f"Class 10 / SSC indicators detected ({', '.join(matches[:3])})")

    if any(b in text_lower for b in ["board", "cbse", "gseb", "icse", "state board", "secondary"]):
        score += 20.0
        reasons.append("Secondary education board header detected")

    if any(m in text_lower for m in ["marks", "subject", "percentage", "grade", "total", "passed"]):
        score += 20.0
        reasons.append("Marksheet academic subjects and grading indicators present")

    if any(t in filename.lower() for t in ["10th", "tenth", "ssc", "matric"]):
        score += 15.0
        reasons.append("Filename matches 10th marksheet")

    # GSEB board name is "Gujarat Secondary & Higher Secondary Education Board"
    # Only penalize if it specifies higher secondary WITHOUT secondary
    is_gseb_combined = "secondary & higher secondary" in text_lower or "secondary and higher secondary" in text_lower
    if not is_gseb_combined and ("higher secondary" in text_lower or "class xii" in text_lower or "hsc" in text_lower or "12th" in text_lower):
        score -= 40.0
    if "bachelor" in text_lower or "cgpa" in text_lower or "sgpa" in text_lower:
        score -= 30.0

    return max(0.0, score), reasons


def calculate_twelfth_score(text: str, filename: str = "") -> Tuple[float, List[str]]:
    text_lower = text.lower()
    score = 0.0
    reasons = []

    if any(k in text_lower for k in ["work experience", "career objective", "professional summary", "projects", "technical skills"]):
        return 0.0, ["Contains resume sections (not a marksheet)"]
    if any(k in text_lower for k in ["assignment", "homework", "syllabus", "question 1", "invoice"]):
        return 0.0, ["Contains assignment/invoice indicators"]

    matches = [kw for kw in TWELFTH_MARKSHEET_KEYWORDS if kw in text_lower]
    if matches:
        score += min(50.0, len(matches) * 20.0)
        reasons.append(f"Class 12 / HSC indicators detected ({', '.join(matches[:3])})")

    # Only credit higher secondary if it is NOT just part of the combined GSEB header on an SSC marksheet
    is_gseb_combined = "secondary & higher secondary" in text_lower or "secondary and higher secondary" in text_lower
    if not is_gseb_combined and any(b in text_lower for b in ["board", "cbse", "gseb", "hsc", "higher secondary", "intermediate"]):
        score += 20.0
        reasons.append("Higher secondary education board header detected")

    if any(m in text_lower for m in ["marks", "subject", "percentage", "grade", "total", "physics", "chemistry", "mathematics", "commerce"]):
        score += 20.0
        reasons.append("12th academic subjects and grading indicators present")

    if any(t in filename.lower() for t in ["12th", "twelfth", "hsc", "intermediate"]):
        score += 15.0
        reasons.append("Filename matches 12th marksheet")

    # Penalize if it explicitly contains 10th / SSC indicators
    if "secondary school examination" in text_lower or "s.s.c" in text_lower or "secondary school certificate" in text_lower or "social science" in text_lower:
        score -= 40.0
    if "diploma in" in text_lower or "polytechnic" in text_lower:
        score -= 30.0

    return max(0.0, score), reasons


def calculate_diploma_score(text: str, filename: str = "") -> Tuple[float, List[str]]:
    text_lower = text.lower()
    score = 0.0
    reasons = []

    if any(k in text_lower for k in ["work experience", "career objective", "professional summary", "projects", "technical skills"]):
        return 0.0, ["Contains resume sections (not a marksheet)"]
    if any(k in text_lower for k in ["assignment", "homework", "syllabus", "question 1", "invoice"]):
        return 0.0, ["Contains assignment/invoice indicators"]

    matches = [kw for kw in DIPLOMA_MARKSHEET_KEYWORDS if kw in text_lower]
    if matches:
        score += min(60.0, len(matches) * 25.0)
        reasons.append(f"Diploma / Polytechnic indicators detected ({', '.join(matches[:3])})")

    if any(b in text_lower for b in ["technical examination", "technical education", "polytechnic", "gtu"]):
        score += 25.0
        reasons.append("Technical education board detected")

    if any(m in text_lower for m in ["grade report", "grade sheet", "statement of marks", "transcript"]):
        score += 20.0
        reasons.append("Diploma grade report markers present")

    if "cgpa" in text_lower or "cumulative grade" in text_lower:
        score += 20.0

    if any(t in filename.lower() for t in ["diploma", "polytechnic"]):
        score += 25.0
        reasons.append("Filename matches Diploma document")

    return max(0.0, score), reasons


def calculate_ug_score(text: str, filename: str = "") -> Tuple[float, List[str]]:
    text_lower = text.lower()
    score = 0.0
    reasons = []

    # Disqualify if it has resume/assignment sections
    if any(k in text_lower for k in ["work experience", "career objective", "professional summary", "academic projects", "projects\n", "technical skills"]):
        return 0.0, ["Contains resume sections (not a marksheet)"]
    if any(k in text_lower for k in ["assignment 1", "assignment 2", "homework", "syllabus", "question 1", "submission instructions", "invoice"]):
        return 0.0, ["Contains assignment/invoice indicators"]
    if "diploma" in text_lower or "polytechnic" in text_lower:
        return 0.0, ["Document indicates Diploma/Polytechnic instead of UG Degree"]

    # Strong marksheet indicators
    strong_marksheet_markers = [
        "grade card", "grade sheet", "transcript", "statement of marks",
        "grade report", "semester grade", "provisional grade report", "end semester examination"
    ]
    strong_matches = [m for m in strong_marksheet_markers if m in text_lower]
    if strong_matches:
        score += min(60.0, len(strong_matches) * 30.0)
        reasons.append(f"Marksheet title detected ({', '.join(strong_matches[:2])})")
    elif any(k in filename.lower() for k in ["marksheet", "grade", "transcript", "sem"]):
        score += 25.0

    if "sgpa" in text_lower:
        score += 25.0
        reasons.append("Semester SGPA indicator present")
    elif "cgpa" in text_lower and ("semester" in text_lower or "examination" in text_lower):
        score += 20.0

    if "credits" in text_lower or "credit points" in text_lower:
        score += 15.0

    matches = [kw for kw in UG_MARKSHEET_KEYWORDS if kw in text_lower]
    if matches:
        score += min(30.0, len(matches) * 10.0)

    if any(u in text_lower for u in ["university", "institute of technology", "gsfc university", "gtu"]):
        score += 10.0

    return max(0.0, score), reasons


def classify_document(text: str, filename: str = "", target_hint: Optional[str] = None) -> DocumentClassificationResult:
    """
    Main document classification pipeline.
    Accurately classifies text across:
    - RESUME
    - TENTH_MARKSHEET
    - TWELFTH_MARKSHEET
    - DIPLOMA_MARKSHEET
    - UG_MARKSHEET
    - OTHER_DOCUMENT / UNCERTAIN
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
    if word_count < 10:
        return DocumentClassificationResult(
            document_type=DocumentTypeEnum.OTHER_DOCUMENT,
            confidence=0.10,
            is_resume=False,
            raw_score=10.0,
            detected_sections=[],
            reasons=[f"Document text is too short ({word_count} words)."],
            error="Text length insufficient for verification."
        )

    resume_score, detected_sections, resume_reasons, resume_penalties = calculate_resume_score(text, filename)
    tenth_score, tenth_reasons = calculate_tenth_score(text, filename)
    twelfth_score, twelfth_reasons = calculate_twelfth_score(text, filename)
    diploma_score, diploma_reasons = calculate_diploma_score(text, filename)
    ug_score, ug_reasons = calculate_ug_score(text, filename)

    # Resume priority if detected sections and high score
    is_strong_resume = resume_score >= 55.0 and len(detected_sections) >= 2

    scores = {
        DocumentTypeEnum.RESUME: resume_score,
        DocumentTypeEnum.TENTH_MARKSHEET: tenth_score,
        DocumentTypeEnum.TWELFTH_MARKSHEET: twelfth_score,
        DocumentTypeEnum.DIPLOMA_MARKSHEET: diploma_score,
        DocumentTypeEnum.UG_MARKSHEET: ug_score,
    }

    if is_strong_resume and resume_score >= max(tenth_score, twelfth_score, diploma_score, ug_score) * 0.8:
        best_type = DocumentTypeEnum.RESUME
        best_score = resume_score
    else:
        best_type = max(scores, key=scores.get)
        best_score = scores[best_type]

    # Target hint weighting if caller specified intent
    if target_hint:
        hint_clean = target_hint.upper()
        if "RESUME" in hint_clean and resume_score >= 35.0:
            best_type = DocumentTypeEnum.RESUME
            best_score = max(best_score, min(100.0, resume_score + 25.0))
        elif "TENTH" in hint_clean and tenth_score >= 35.0:
            best_type = DocumentTypeEnum.TENTH_MARKSHEET
            best_score = max(best_score, tenth_score)
        elif "TWELFTH" in hint_clean and twelfth_score >= 35.0 and twelfth_score >= diploma_score:
            best_type = DocumentTypeEnum.TWELFTH_MARKSHEET
            best_score = max(best_score, twelfth_score)
        elif ("DIPLOMA" in hint_clean or "TWELFTH_OR_DIPLOMA" in hint_clean) and diploma_score >= 35.0:
            best_type = DocumentTypeEnum.DIPLOMA_MARKSHEET
            best_score = max(best_score, diploma_score)
        elif "UG" in hint_clean and ug_score >= 35.0:
            best_type = DocumentTypeEnum.UG_MARKSHEET
            best_score = max(best_score, ug_score)

    confidence = min(1.00, max(0.00, best_score / 100.0))
    is_resume = best_type == DocumentTypeEnum.RESUME and confidence >= RESUME_CONFIDENCE_THRESHOLD

    # Determine final document type
    if best_score < 40.0:
        final_doc_type = DocumentTypeEnum.OTHER_DOCUMENT
    else:
        final_doc_type = best_type

    reasons_map = {
        DocumentTypeEnum.RESUME: resume_reasons + resume_penalties,
        DocumentTypeEnum.TENTH_MARKSHEET: tenth_reasons,
        DocumentTypeEnum.TWELFTH_MARKSHEET: twelfth_reasons,
        DocumentTypeEnum.DIPLOMA_MARKSHEET: diploma_reasons,
        DocumentTypeEnum.UG_MARKSHEET: ug_reasons,
    }
    all_reasons = reasons_map.get(final_doc_type, ["Classification determined based on keyword density and layout."])

    return DocumentClassificationResult(
        document_type=final_doc_type,
        confidence=round(confidence, 2),
        is_resume=is_resume,
        raw_score=round(best_score, 1),
        detected_sections=detected_sections if final_doc_type == DocumentTypeEnum.RESUME else [final_doc_type.value],
        reasons=all_reasons,
        error=None if confidence >= 0.50 else f"Classification confidence ({int(confidence * 100)}%) is too low."
    )
