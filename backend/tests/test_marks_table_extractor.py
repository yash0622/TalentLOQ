"""
Unit tests for 10th & 12th Marks Table Extraction and Percentage Calculation System.
"""
import pytest
from app.document_detection.marks_table_extractor import MarksTableExtractor


def test_standard_cbse_5_subjects():
    text = """
    CENTRAL BOARD OF SECONDARY EDUCATION
    SECONDARY SCHOOL EXAMINATION (CLASS X) 2022
    CANDIDATE NAME: JAITRA PATHAK   ROLL NO: 1234567

    SUB CODE  SUB NAME                THEORY  PRACTICAL  TOTAL  MAX MARKS  GRADE
    184       ENGLISH LANG & LIT       075     020        095    100        A1
    002       HINDI COURSE-A           065     020        085    100        A1
    041       MATHEMATICS STANDARD     058     020        078    100        B1
    086       SCIENCE                  060     020        080    100        A2
    087       SOCIAL SCIENCE           070     020        090    100        A1
    501       HEALTH & PHYSICAL EDU    --      --         --     --         A1
    502       WORK EXPERIENCE          --      --         --     --         A1

    TOTAL MARKS: 428 / 500
    RESULT: PASS
    """
    res = MarksTableExtractor.extract(text, exam_type="10th")
    assert res["exam"] == "10th"
    assert res["total_subjects"] == 5
    # Total = 95 + 85 + 78 + 80 + 90 = 428
    assert res["total_marks_obtained"] == 428.0
    assert res["total_max_marks"] == 500.0
    assert res["percentage"] == 85.60
    assert res["total_marks_display"] == "428/500"

    # Ensure excluded subjects are not present
    subject_names = [s["subject_name"].lower() for s in res["subjects"]]
    assert not any("health" in n for n in subject_names)
    assert not any("work" in n for n in subject_names)


def test_gseb_state_board_marksheet():
    text = """
    GUJARAT SECONDARY AND HIGHER SECONDARY EDUCATION BOARD
    SEAT NO: B123456 CANDIDATE NAME: JAITRA PATHAK

    SUB CODE SUB NAME TOTAL MARKS MARKS OBTAINED RESULT
    01 GUJARATI (FL) 100 074 PASS
    02 SOCIAL SCIENCE 100 068 PASS
    03 SCIENCE & TECH 100 071 PASS
    04 MATHEMATICS 100 082 PASS
    05 ENGLISH (SL) 100 065 PASS
    10 BASIC COMPUTER (P) 050 042 PASS
    RESULT: PASS
    """
    res = MarksTableExtractor.extract(text, exam_type="10th")
    assert res["total_subjects"] == 5
    # Total = 74 + 68 + 71 + 82 + 65 = 360
    assert res["total_marks_obtained"] == 360.0
    assert res["total_max_marks"] == 500.0
    assert res["percentage"] == 72.00


def test_twelfth_science_with_normalized_marks():
    text = """
    CENTRAL BOARD OF SECONDARY EDUCATION
    SENIOR SCHOOL CERTIFICATE EXAMINATION (CLASS XII) 2024
    NAME: JAITRA PATHAK

    SUB CODE  SUB NAME               MARKS OBTAINED  MAX MARKS
    301       ENGLISH CORE            85              100
    042       PHYSICS                 70              100
    043       CHEMISTRY               75              100
    041       MATHEMATICS             90              100
    083       COMPUTER SCIENCE        95              100
    500       WORK EXPERIENCE         --              --
    502       PHYSICAL EDUCATION      --              --
    """
    res = MarksTableExtractor.extract(text, exam_type="12th")
    assert res["exam"] == "12th"
    assert res["total_subjects"] == 5
    # Total = 85 + 70 + 75 + 90 + 95 = 415
    assert res["total_marks_obtained"] == 415.0
    assert res["total_max_marks"] == 500.0
    assert res["percentage"] == 83.00


def test_custom_subject_count_and_different_max_marks():
    text = """
    BOARD EXAMINATION RESULT
    STUDENT: TEST CANDIDATE
    
    MATHEMATICS: 45 / 50
    PHYSICS: 72 / 80
    CHEMISTRY: 85 / 100
    ENGLISH: 80 / 100
    """
    res = MarksTableExtractor.extract(text, exam_type="12th")
    assert res["total_subjects"] == 4
    # Total obtained = 45 + 72 + 85 + 80 = 282
    # Total max = 50 + 80 + 100 + 100 = 330
    assert res["total_marks_obtained"] == 282.0
    assert res["total_max_marks"] == 330.0
    # Percentage = (282 / 330) * 100 = 85.45%
    assert res["percentage"] == 85.45
    
    # Check normalization out of 100
    math_sub = next(s for s in res["subjects"] if "math" in s["subject_name"].lower())
    assert math_sub["normalized_100"] == 90.0  # 45/50 * 100 = 90.0


def test_gseb_6_subjects_total_464():
    text = """
    (Examination Wing, Secondary)
    STATEMENT OF MARKS
    SOLANK YASHKUMAR
    SUBJECT SubJECT Wise MaAKS Obtained EVALUATOH GAAND TOTAL words Wise GRADE
    GUJARATI 68 085 EIGHT FIVE A2
    SOCIAL
    SC IENCE 50 14 064 SIX FOUR B2
    SC IENCE 56 19 075 SEVEN FIVE B1
    MATHEMATICS 60 16 076 SEVEN SIX B 1
    16
    ENGL ISH SL 61 17 078 SEVEN EIGHT B 1
    17
    SANSKRIT 70 16 086 EIchT SIX A2
    Total:
    464
    GRAND TOTAL Of MARKS OBTAINED
    FOUR HUNDRED SIXTY FOUR
    """
    res = MarksTableExtractor.extract(text, exam_type="10th")
    assert res["total_subjects"] == 6
    assert res["total_marks_obtained"] == 464.0
    assert res["total_max_marks"] == 600.0
    assert res["percentage"] == 77.33
    assert res["total_marks_display"] == "464/600"
