import pytest
from app.document_detection.extractor import _reconstruct_spatial_layout_from_data
from app.document_detection.marks_table_extractor import MarksTableExtractor
from app.document_detection.parsers import (
    fuzzy_match_skill,
    fuzzy_match_institution,
    CANONICAL_SKILLS_MAP,
    KNOWN_BOARDS,
    UNIVERSITY_MAP,
    ResumeParser,
    TenthMarksheetParser,
)

def test_spatial_layout_reconstruction():
    """Verifies that bounding-box tokens are grouped horizontally and separated into columns."""
    sample_data = {
        "text": ["041", "MATHEMATICS", "85", "100", "A1"],
        "top": [100, 102, 101, 100, 102],
        "height": [15, 14, 15, 15, 14],
        "left": [50, 100, 300, 380, 450],
        "conf": [95, 95, 95, 95, 95]
    }
    reconstructed = _reconstruct_spatial_layout_from_data(sample_data)
    assert "MATHEMATICS" in reconstructed
    assert "85" in reconstructed
    assert "100" in reconstructed

def test_self_healing_checksum_correction():
    """Verifies that an OCR digit mistake (e.g. 38 instead of 88) is auto-corrected using Grand Total."""
    # Sum is 414, but Grand Total is 464 (discrepancy 50: 38 was read instead of 88)
    subjects = [
        {"subject_name": "English", "marks_obtained": 80.0, "max_marks": 100.0, "normalized_100": 80.0},
        {"subject_name": "Science", "marks_obtained": 85.0, "max_marks": 100.0, "normalized_100": 85.0},
        {"subject_name": "Mathematics", "marks_obtained": 38.0, "max_marks": 100.0, "normalized_100": 38.0}, # Misread by OCR!
        {"subject_name": "Social Science", "marks_obtained": 75.0, "max_marks": 100.0, "normalized_100": 75.0},
        {"subject_name": "Gujarati", "marks_obtained": 86.0, "max_marks": 100.0, "normalized_100": 86.0},
    ]
    healed_subs, total_obt, pct = MarksTableExtractor._heal_checksum_discrepancies(
        subjects=subjects,
        printed_grand_total=414.0,
        printed_percentage=82.8,
        total_max=500.0
    )
    math_sub = next(s for s in healed_subs if s["subject_name"] == "Mathematics")
    assert math_sub["marks_obtained"] == 88.0
    assert total_obt == 414.0
    assert pct == 82.8

def test_fuzzy_skill_matching():
    """Verifies that OCR typos in resume skills are resolved to canonical casing."""
    assert fuzzy_match_skill("Fluter", CANONICAL_SKILLS_MAP) == "Flutter"
    assert fuzzy_match_skill("TypeScrip", CANONICAL_SKILLS_MAP) == "TypeScript"
    assert fuzzy_match_skill("Pythn", CANONICAL_SKILLS_MAP) == "Python"
    assert fuzzy_match_skill("Kubernets", CANONICAL_SKILLS_MAP) == "Kubernetes"

def test_fuzzy_institution_matching():
    """Verifies that Indian universities and boards are matched despite minor OCR variations."""
    text_sample = "Candidate completed examination from ITM Baroda Univ Vadodara"
    assert fuzzy_match_institution(text_sample, UNIVERSITY_MAP) == "ITM (SLS) Baroda University"

    text_board = "Gujarat Secondary and Higher Sec Education Board"
    assert fuzzy_match_institution(text_board, KNOWN_BOARDS) == "Gujarat Secondary and Higher Secondary Education Board (GSEB)"

def test_resume_parser_with_fuzzy_skills():
    """Verifies that ResumeParser extracts skills even if typed with minor OCR typos."""
    resume_text = """
    John Doe
    john@example.com
    Technical Skills: Fluter, Pythn, TypeScrip, Dart, FastApi, Docker, Git, SQL
    """
    parsed = ResumeParser.parse(resume_text)
    assert "Flutter" in parsed["skills"]
    assert "Python" in parsed["skills"]
    assert "TypeScript" in parsed["skills"]
    assert "Dart" in parsed["skills"]
