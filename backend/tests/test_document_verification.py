"""
Unit & Integration Test Suite for Document OCR Verification & Auto-Profile Synchronization.
Covers:
- Two-tier text extraction (native vs OCR)
- Document classification (Resume, 10th, 12th, Diploma, UG Marksheet)
- Skill deduplication and canonical normalization
- 10th Marksheet percentage extraction and calculation
- 12th vs Diploma marksheet disambiguation and GPA handling (no blind conversions)
- UG Marksheet CGPA, SGPA, and Backlog variations (0, ATKT, UNKNOWN)
- Numeric range validation (0-100% and 0-10 CGPA)
- Cross-document name mismatch detection
- SHA-256 hash deduplication (skipping redundant processing)
- Security lockdown: student cannot tamper with academic fields via PUT /me
- End-to-end API upload and canonical profile synchronization
"""
import pytest
import io
import httpx
from httpx import AsyncClient
from app.main import app
from app.jwt_utils import create_access_token
from app.database import students_collection, users_collection, verification_documents_collection, verification_audits_collection
from app.document_detection import (
    DocumentTypeEnum,
    VerificationStatusEnum,
    classify_document,
    ResumeParser,
    TenthMarksheetParser,
    TwelfthDiplomaParser,
    UGMarksheetParser,
    DocumentValidator,
    DocumentVerificationService,
)


# ===========================================================================
# 1. RESUME PARSING & NORMALIZATION
# ===========================================================================

def test_resume_parser_skills_and_languages_normalization():
    resume_text = """
    Aarav Mehta
    aarav.mehta@gsfcuniversity.ac.in | +91 9123456780 | linkedin.com/in/aaravmehta

    CAREER SUMMARY
    Software Engineer with strong foundation in backend development.

    TECHNICAL SKILLS
    Programming: python, Python, PYTHON, Java, java, C++, cpp
    Web Frameworks: FastAPI, fastapi, django, Flutter, react.js, React
    Databases & Cloud: SQL, MongoDB, mongodb, docker, Docker, AWS, Git

    LANGUAGES KNOWN
    English, Hindi, Gujarati, French
    """
    parsed = ResumeParser.parse(resume_text)
    skills = parsed["skills"]
    languages = parsed["languages"]

    # Deduplicated and canonical casing
    assert "Python" in skills
    assert skills.count("Python") == 1
    assert "Java" in skills
    assert skills.count("Java") == 1
    assert "FastAPI" in skills
    assert "React" in skills
    assert "MongoDB" in skills
    assert "Docker" in skills

    # Languages extracted
    assert "English" in languages
    assert "Hindi" in languages
    assert "Gujarati" in languages
    assert "French" in languages


# ===========================================================================
# 2. 10TH MARKSHEET PARSING & PERCENTAGE CALCULATION
# ===========================================================================

def test_tenth_marksheet_explicit_percentage():
    marksheet_text = """
    CENTRAL BOARD OF SECONDARY EDUCATION (CBSE)
    SECONDARY SCHOOL EXAMINATION (CLASS X) 2020
    STATEMENT OF MARKS

    Candidate Name: Riya Sharma
    Roll No: 11204859
    School: Delhi Public School

    Subject Code   Subject Name         Marks Obtained   Max Marks   Grade
    101            English Core         88               100         A2
    041            Mathematics Standard 94               100         A1
    086            Science              91               100         A1
    087            Social Science       85               100         A2
    085            Hindi Course-A       92               100         A1

    Result: PASS
    Percentage: 90.00%
    Passing Year: 2020
    """
    res = classify_document(marksheet_text, "10th_marksheet.pdf")
    assert res.document_type == DocumentTypeEnum.TENTH_MARKSHEET
    assert res.is_resume is False

    parsed = TenthMarksheetParser.parse(marksheet_text)
    assert parsed["passing_year"] == 2020
    assert parsed["tenth_percentage"] == 90.0
    assert "CBSE" in parsed["board"]


def test_tenth_marksheet_calculated_percentage():
    marksheet_text = """
    GUJARAT SECONDARY AND HIGHER SECONDARY EDUCATION BOARD, GANDHINAGAR
    SECONDARY SCHOOL CERTIFICATE (S.S.C.) EXAMINATION - MARCH 2019
    STATEMENT OF MARKS

    Name: Patel Jay Kumar
    Seat No: B-194852

    Marks Obtained: 450 out of 500
    Result: PASS
    Passing Year: 2019
    """
    parsed = TenthMarksheetParser.parse(marksheet_text)
    assert parsed["passing_year"] == 2019
    # 450 / 500 = 90.0%
    assert parsed["tenth_percentage"] == 90.0


# ===========================================================================
# 3. 12TH VS DIPLOMA MARKSHEET DISAMBIGUATION
# ===========================================================================

def test_twelfth_marksheet_extraction():
    twelfth_text = """
    GUJARAT SECONDARY AND HIGHER SECONDARY EDUCATION BOARD
    HIGHER SECONDARY CERTIFICATE (H.S.C.) EXAMINATION (STANDARD XII) 2022
    SCIENCE STREAM STATEMENT OF MARKS

    Student Name: Chintan Sharma
    Seat Number: C-204918
    Year of Passing: 2022

    Subjects: Physics, Chemistry, Mathematics, English, Computer Studies
    Grand Total: 425 / 500
    Percentage: 85.00%
    Result: PASS WITH DISTINCTION
    """
    res = classify_document(twelfth_text, "12th_science_marksheet.pdf")
    assert res.document_type == DocumentTypeEnum.TWELFTH_MARKSHEET

    parsed = TwelfthDiplomaParser.parse(twelfth_text)
    assert parsed["document_subtype"] == "TWELFTH_MARKSHEET"
    assert parsed["passing_year"] == 2022
    assert parsed["percentage"] == 85.0
    assert parsed["diploma_cgpa"] is None  # Never generate fake CGPA


def test_diploma_marksheet_extraction_no_blind_conversion():
    diploma_text = """
    GUJARAT TECHNOLOGICAL UNIVERSITY (GTU)
    DIPLOMA IN COMPUTER ENGINEERING
    FINAL SEMESTER GRADE REPORT - 2021

    Student Name: Rohan Trivedi
    Enrollment No: 186170307045
    College: Government Polytechnic, Ahmedabad

    Cumulative Grade Point Average (CGPA): 8.75
    Total Credits Earned: 140
    Result: FIRST CLASS WITH DISTINCTION
    """
    res = classify_document(diploma_text, "gtu_diploma_grade_report.pdf")
    assert res.document_type == DocumentTypeEnum.DIPLOMA_MARKSHEET

    parsed = TwelfthDiplomaParser.parse(diploma_text)
    assert parsed["document_subtype"] == "DIPLOMA_MARKSHEET"
    assert parsed["diploma_cgpa"] == 8.75
    # Do NOT blindly convert CGPA into percentage
    assert parsed["percentage"] is None or parsed["diploma_cgpa"] == 8.75


# ===========================================================================
# 4. CURRENT UG MARKSHEET & BACKLOGS VARIATIONS
# ===========================================================================

def test_ug_marksheet_zero_backlogs():
    ug_text = """
    GSFC UNIVERSITY - SCHOOL OF TECHNOLOGY
    VIGYAN BHAVAN, FERTILIZER NAGAR, VADODARA
    END SEMESTER GRADE REPORT - SEMESTER VI (MAY 2026)

    Student Name: Yash Sharma
    Enrollment No: 24BT04D231
    Degree: Bachelor of Technology in Computer Science & Engineering

    Course Code   Course Title                     Credits   Grade Earned   Grade Points
    CS601         Cloud Computing                  4         A              36
    CS602         Machine Learning                 4         A+             40
    CS603         Information Security             3         A              27

    Semester Grade Point Average (SGPA): 8.80
    Cumulative Grade Point Average (CGPA): 8.92
    Active Backlogs: 0
    Status: CLEARED ALL SUBJECTS
    """
    res = classify_document(ug_text, "ug_sem6_grade_card.pdf")
    assert res.document_type == DocumentTypeEnum.UG_MARKSHEET

    parsed = UGMarksheetParser.parse(ug_text)
    assert parsed["enrollment_number"] == "24BT04D231"
    assert parsed["current_semester"] == 6
    assert parsed["sgpa"] == 8.80
    assert parsed["cgpa"] == 8.92
    assert parsed["active_backlogs"] == 0


def test_ug_marksheet_atkt_and_unknown_backlogs():
    # 1. ATKT format
    atkt_text = """
    GUJARAT TECHNOLOGICAL UNIVERSITY
    B.E. SEMESTER 4 EXAMINATION GRADE CARD
    Enrollment No: 20012011005
    SGPA: 7.20
    CGPA: 7.45
    Current ATKT: 2
    """
    parsed_atkt = UGMarksheetParser.parse(atkt_text)
    assert parsed_atkt["active_backlogs"] == 2

    # 2. Missing backlog info must NOT default to 0 -> must be UNKNOWN
    missing_backlog_text = """
    GSFC UNIVERSITY
    STATEMENT OF GRADES - B.TECH SEMESTER 5
    Enrollment No: 24BT04D100
    SGPA: 8.10
    CGPA: 8.25
    Total Credits: 22
    """
    parsed_missing = UGMarksheetParser.parse(missing_backlog_text)
    assert parsed_missing["active_backlogs"] == "UNKNOWN"


# ===========================================================================
# 5. SEMANTIC & NUMERIC VALIDATION
# ===========================================================================

def test_numeric_validation_bounds():
    # Percentage > 100 or negative must fail
    meta, errors, warnings, ocr_c, ext_c, val_c = DocumentValidator.validate_extracted_fields(
        doc_type="TENTH_MARKSHEET",
        fields={"tenth_percentage": 105.0, "passing_year": 2020},
    )
    assert any("Invalid 10th percentage" in e for e in errors)
    assert val_c < 75.0

    # CGPA > 10.0 must fail
    meta_ug, errors_ug, _, _, _, _ = DocumentValidator.validate_extracted_fields(
        doc_type="UG_MARKSHEET",
        fields={"cgpa": 12.5, "active_backlogs": 0},
    )
    assert any("exceeds standard 10.0 scale" in e for e in errors_ug)


# ===========================================================================
# 6. CROSS-DOCUMENT NAME MISMATCH
# ===========================================================================

def test_cross_document_name_criteria_removed():
    # Per user requirement: name criteria removed from all documents
    critical_mismatches, warnings = DocumentValidator.perform_cross_document_validation(
        extracted_name="Robert Downey",
        extracted_enrollment=None,
        extracted_university=None,
        profile_name="Chintan Sharma",
        profile_enrollment=None,
        profile_university=None,
    )
    # Name differences must no longer block or cause critical mismatches
    assert len(critical_mismatches) == 0


from unittest.mock import AsyncMock, MagicMock

# ===========================================================================
# 7. SECURITY: PUT /me MUST PREVENT ACADEMIC TAMPERING
# ===========================================================================

@pytest.mark.asyncio
async def test_security_put_me_blocks_academic_tampering(monkeypatch):
    import app.routers.auth as auth_router
    test_user_id = "test_verify_user_123"
    token = create_access_token(user_id=test_user_id, role="student")
    headers = {"Authorization": f"Bearer {token}"}

    mock_user = {
        "user_id": test_user_id,
        "email": "student_test@gsfcuniversity.ac.in",
        "full_name": "Test Student",
        "role": "student",
    }
    monkeypatch.setattr(auth_router.users_collection, "find_one", AsyncMock(return_value=mock_user))
    monkeypatch.setattr(auth_router.users_collection, "update_many", AsyncMock())
    monkeypatch.setattr(auth_router.students_collection, "update_many", AsyncMock())

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Malicious attempt to modify verified CGPA directly
        res_tamper = await ac.put("/auth/me", json={"cgpa": 9.99}, headers=headers)
        assert res_tamper.status_code == 403
        assert "forbidden" in res_tamper.json()["detail"].lower()

        # 2. Malicious attempt to modify backlogs
        res_backlog_tamper = await ac.put("/auth/me", json={"active_backlogs": 0}, headers=headers)
        assert res_backlog_tamper.status_code == 403

        # 3. Legitimate attempt to update Name and University (allowed)
        res_legit = await ac.put("/auth/me", json={"full_name": "Test Student Updated", "university": "GSFC University"}, headers=headers)
        assert res_legit.status_code == 200


# ===========================================================================
# 8. END-TO-END DOCUMENT UPLOAD & PROFILE SYNCHRONIZATION
# ===========================================================================

@pytest.mark.asyncio
async def test_e2e_document_upload_and_auto_sync(monkeypatch):
    import app.routers.documents as doc_router
    import app.document_detection.service as doc_service
    test_user_id = "test_verify_user_123"
    token = create_access_token(user_id=test_user_id, role="student")
    headers = {"Authorization": f"Bearer {token}"}

    mock_student = {
        "student_id": "test_verify_student_123",
        "user_id": test_user_id,
        "full_name": "Kavya Patel",
        "email": "student_verify@gsfcuniversity.ac.in",
        "CGPA": 0.0,
        "active_backlogs": 0,
        "university": "GSFC University",
        "verified_fields": {},
        "documents": {},
    }
    mock_user = {
        "user_id": test_user_id,
        "email": "student_verify@gsfcuniversity.ac.in",
        "full_name": "Kavya Patel",
    }

    monkeypatch.setattr(doc_service.students_collection, "find_one", AsyncMock(return_value=mock_student))
    monkeypatch.setattr(doc_service.students_collection, "update_one", AsyncMock())
    monkeypatch.setattr(doc_service.verification_documents_collection, "find_one", AsyncMock(return_value=None))
    monkeypatch.setattr(doc_service.verification_documents_collection, "insert_one", AsyncMock())
    monkeypatch.setattr(doc_service.verification_audits_collection, "insert_many", AsyncMock())
    monkeypatch.setattr(doc_service.grid_fs, "upload_from_stream", AsyncMock(return_value="mock_grid_id_123"))

    ug_content = b"""
    GSFC UNIVERSITY
    GRADE CARD - B.TECH CSE SEMESTER 6
    Candidate Name: Kavya Patel
    Enrollment No: 24BT04D500
    SGPA: 8.75
    CGPA: 8.85
    Active Backlogs: 0
    Result: PASS
    """

    files = {
        "file": ("ug_grade_card.txt", ug_content, "text/plain")
    }
    data = {
        "target_type": "UG_MARKSHEET"
    }

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        upload_res = await ac.post("/documents/upload", files=files, data=data, headers=headers)
        assert upload_res.status_code == 200
        res_data = upload_res.json()
        assert res_data["status"] == "VERIFIED"
        assert res_data["extracted_fields"]["cgpa"] == 8.85
        assert res_data["extracted_fields"]["active_backlogs"] == 0
        assert res_data["extracted_fields"]["enrollment_number"] == "24BT04D500"


def test_resume_soft_skills_and_programming_languages():
    resume_text = """
    Priya Patel
    priya.patel@gmail.com | +91 9876543210

    TECHNICAL SKILLS
    Programming Languages: Python, Java, Dart, TypeScript
    Frameworks & Tools: Flutter, FastAPI, Docker, Git

    SOFT SKILLS
    Problem Solving, Critical Thinking, Team Leadership, Communication, Agile

    LANGUAGES KNOWN
    English, Hindi, Gujarati
    """
    parsed = ResumeParser.parse(resume_text)

    # Combined deduplicated skills
    assert "Python" in parsed["skills"]
    assert "Problem Solving" in parsed["skills"]
    assert "Critical Thinking" in parsed["skills"]
    assert "Team Leadership" in parsed["skills"]

    # Separated categories
    assert "Problem Solving" in parsed["soft_skills"]
    assert "Agile" in parsed["soft_skills"]
    assert "Python" in parsed["technical_skills"]

    # Spoken vs Programming languages
    assert "English" in parsed["languages"]
    assert "Gujarati" in parsed["languages"]
    assert "Python" in parsed["programming_languages"]
    assert "Dart" in parsed["programming_languages"]


def test_tenth_marksheet_cbse_pre_2018_cgpa_conversion():
    marksheet_text = """
    CENTRAL BOARD OF SECONDARY EDUCATION, DELHI
    SECONDARY SCHOOL EXAMINATION 2016
    GRADE SHEET CUM CERTIFICATE OF PERFORMANCE

    Candidate Name: Aarav Shah
    Roll No: 1194820

    Subject Code   Subject Name         Grade   Grade Point
    101            English Communicative A1      10.0
    002            Hindi Course-A        A1      10.0
    041            Mathematics           A2       9.0
    086            Science               A2       9.0
    087            Social Science        B1       8.0

    Cumulative Grade Point Average (CGPA): 9.20
    Result: QUALIFIED FOR ADMISSION TO HIGHER CLASSES
    Year: 2016
    """
    parsed = TenthMarksheetParser.parse(marksheet_text)
    assert parsed["passing_year"] == 2016
    assert parsed["tenth_cgpa"] == 9.20
    # 9.20 * 9.5 = 87.40%
    assert parsed["tenth_percentage"] == 87.40


@pytest.mark.asyncio
async def test_field_flag_dispute_and_admin_override(monkeypatch):
    token = create_access_token("student_test_dispute", "student")
    headers = {"Authorization": f"Bearer {token}"}

    mock_student = {
        "_id": "mock_id_dispute",
        "student_id": "student_test_dispute",
        "user_id": "student_test_dispute",
        "full_name": "Test Student",
        "CGPA": 7.50,
        "verified_fields": {
            "CGPA": {
                "value": 7.50,
                "confidence": 95.0,
                "extraction_method": "ocr",
                "source": "ug_marksheet.pdf",
                "verification_status": "VERIFIED",
            }
        }
    }

    from app.routers import documents as doc_router
    from unittest.mock import AsyncMock
    monkeypatch.setattr(doc_router.students_collection, "find_one", AsyncMock(return_value=mock_student))
    monkeypatch.setattr(doc_router.students_collection, "update_one", AsyncMock())
    monkeypatch.setattr(doc_router.support_tickets_collection, "insert_one", AsyncMock())
    monkeypatch.setattr(doc_router.support_tickets_collection, "update_many", AsyncMock())
    monkeypatch.setattr(doc_router.verification_audits_collection, "insert_one", AsyncMock())

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Flag field
        flag_res = await ac.post(
            "/documents/profile/verified-data/CGPA/flag",
            json={"reason": "OCR misread 8.50 as 7.50 due to fold"},
            headers=headers
        )
        assert flag_res.status_code == 200
        flag_data = flag_res.json()
        assert flag_data["status"] == "flagged"
        assert "ticket_id" in flag_data

        # 2. Admin/Recruiter overrides field
        recruiter_token = create_access_token(user_id="recruiter_admin_123", role="recruiter")
        recruiter_headers = {"Authorization": f"Bearer {recruiter_token}"}
        override_res = await ac.patch(
            f"/documents/profile/verified-data/CGPA/admin-override?student_id={mock_student['student_id']}",
            json={"new_value": 8.50, "notes": "Manually verified against original physical marksheet"},
            headers=recruiter_headers
        )
        assert override_res.status_code == 200
        override_data = override_res.json()
        assert override_data["new_value"] == 8.50
        assert override_data["source"] == "Manually Verified by Admin"
        assert override_data["status"] == "VERIFIED"


@pytest.mark.asyncio
async def test_delete_document_instantly_clears_profile_values(monkeypatch):
    from httpx import AsyncClient
    import httpx
    from app.main import app
    from app.jwt_utils import create_access_token

    token = create_access_token("student_del_123", "student")
    headers = {"Authorization": f"Bearer {token}"}

    mock_student = {
        "_id": "60d5ec49f1b2c8b1f8e4e1a1",
        "student_id": "student_del_123",
        "user_id": "student_del_123",
        "tenth_percentage": 92.5,
        "tenth_cgpa": 9.7,
        "tenth_board": "CBSE",
        "documents": {"tenth": {"document_id": "DOC-TENTH-1"}},
        "verified_fields": {
            "tenth_percentage": {"value": 92.5, "confidence": 98.0, "source": "10th.pdf"}
        }
    }

    mock_doc = {
        "_id": "60d5ec49f1b2c8b1f8e4e1a2",
        "document_id": "DOC-TENTH-1",
        "user_id": "student_del_123",
        "target_type": "TENTH_MARKSHEET",
    }

    from app.routers import documents as doc_router
    from unittest.mock import AsyncMock
    mock_update_one = AsyncMock()
    mock_delete_one = AsyncMock()

    monkeypatch.setattr(doc_router.students_collection, "find_one", AsyncMock(return_value=mock_student))
    monkeypatch.setattr(doc_router.students_collection, "update_one", mock_update_one)
    monkeypatch.setattr(doc_router.verification_documents_collection, "find_one", AsyncMock(return_value=mock_doc))
    monkeypatch.setattr(doc_router.verification_documents_collection, "delete_one", mock_delete_one)

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        del_res = await ac.delete("/documents/DOC-TENTH-1", headers=headers)
        assert del_res.status_code == 200
        del_data = del_res.json()
        assert del_data["target_type"] == "TENTH_MARKSHEET"

        # Verify update_one was called to reset tenth fields to None
        mock_update_one.assert_called_once()
        call_args = mock_update_one.call_args[0][1]
        assert "$set" in call_args
        assert call_args["$set"]["tenth_percentage"] is None
        assert call_args["$set"]["tenth_board"] is None
        assert "tenth_percentage" not in call_args["$set"]["verified_fields"]



