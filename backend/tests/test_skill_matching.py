import pytest
from unittest.mock import AsyncMock, MagicMock
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.jwt_utils import create_access_token
from app.services.skill_matcher import skill_matcher_engine

def test_phrase_matcher_extraction():
    """Verify spaCy PhraseMatcher extracts canonical skills accurately from messy text."""
    desc = """
    We are seeking a Backend Software Engineer proficient in Python, FastAPI, and Docker.
    Experience with PostgreSQL and Redis caching is a strong plus.
    Familiarity with Git, Linux, and REST APIs required. Bonus if you know Flutter or AI/ML.
    """
    extracted = skill_matcher_engine.extract_skills_from_text(desc)
    assert "Python" in extracted
    assert "FastAPI" in extracted
    assert "Docker" in extracted
    assert "PostgreSQL" in extracted
    assert "Redis" in extracted
    assert "Git" in extracted
    assert "Linux" in extracted
    assert "REST APIs" in extracted
    assert "Flutter" in extracted
    assert "AI/ML" in extracted

    # Edge cases
    assert skill_matcher_engine.extract_skills_from_text("") == []
    assert skill_matcher_engine.extract_skills_from_text(None) == []
    assert skill_matcher_engine.extract_skills_from_text("   \n\t  ") == []

def test_skill_overlap_computation():
    """Verify deterministic skill overlap arithmetic."""
    cand_skills = ["Python", "Docker", "FastAPI", "React"]
    req_skills = ["Python", "FastAPI", "Kubernetes", "AWS"]

    overlap = skill_matcher_engine.compute_skill_overlap(cand_skills, req_skills)
    assert sorted(overlap["matched_skills"]) == ["FastAPI", "Python"]
    assert sorted(overlap["missing_skills"]) == ["AWS", "Kubernetes"]
    assert overlap["match_count"] == 2
    assert overlap["total_required"] == 4
    assert overlap["is_exact_match"] is False

    # Exact match case
    exact_overlap = skill_matcher_engine.compute_skill_overlap(["Python", "FastAPI"], ["python", "fastapi"])
    assert exact_overlap["is_exact_match"] is True
    assert exact_overlap["match_count"] == 2
    assert len(exact_overlap["missing_skills"]) == 0

@pytest.mark.asyncio
async def test_recruiter_matching_students_endpoint(monkeypatch):
    """Test GET /recruiter/drives/{drive_id}/matching-students with any vs all match_type."""
    import app.routers.drives_recruiter as rec_router

    drive_id = "test-drive-123"
    mock_drive = {
        "drive_id": drive_id,
        "company_name": "Google",
        "drive_title": "Software Engineer",
        "min_cgpa": 7.0,
        "extracted_required_skills": ["Python", "FastAPI", "Docker"],
        "posted_by": "recruiter_1",
    }

    mock_students = [
        {
            "student_id": "stud_1",
            "full_name": "Alice Sharma",
            "email": "alice@test.com",
            "CGPA": 8.5,
            "skills": ["Python", "FastAPI", "Docker", "Git"],
        },
        {
            "student_id": "stud_2",
            "full_name": "Bob Patel",
            "email": "bob@test.com",
            "CGPA": 7.5,
            "skills": ["Python"],
        },
        {
            "student_id": "stud_3",
            "full_name": "Charlie Mehta",
            "email": "charlie@test.com",
            "CGPA": 6.5, # Below 7.0 min_cgpa
            "skills": ["Python", "FastAPI", "Docker"],
        },
    ]

    async def mock_find_one_drive(query):
        if query.get("drive_id") == drive_id:
            return mock_drive
        return None

    class MockStudentsCursor:
        def __init__(self, query):
            self.query = query
        async def to_list(self, length=None):
            results = []
            for s in mock_students:
                # Filter CGPA
                cgpa = s.get("CGPA", 0.0)
                if "$or" in self.query:
                    # check cgpa >= cutoff
                    cutoff = self.query["$or"][0]["CGPA"]["$gte"]
                    if cgpa < cutoff:
                        continue
                results.append(s)
            return results

    def mock_find_students(query):
        return MockStudentsCursor(query)

    monkeypatch.setattr(rec_router.drives_collection, "find_one", mock_find_one_drive)
    monkeypatch.setattr(rec_router.students_collection, "find", mock_find_students)
    monkeypatch.setattr(rec_router.audit_logs_collection, "insert_one", AsyncMock())

    recruiter_token = create_access_token("recruiter_1", "recruiter")
    student_token = create_access_token("stud_1", "student")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # 1. Student access rejected with 403
        res_forbidden = await ac.get(
            f"/recruiter/drives/{drive_id}/matching-students",
            headers={"Authorization": f"Bearer {student_token}"}
        )
        assert res_forbidden.status_code == 403

        # 2. Recruiter match_type=any (Alice and Bob match, Charlie filtered by CGPA)
        res_any = await ac.get(
            f"/recruiter/drives/{drive_id}/matching-students?match_type=any",
            headers={"Authorization": f"Bearer {recruiter_token}"}
        )
        assert res_any.status_code == 200
        data_any = res_any.json()
        assert data_any["total_count"] == 2
        # Alice has 3 matches, Bob has 1 match; Alice should be first
        assert data_any["items"][0]["student_id"] == "stud_1"
        assert data_any["items"][0]["match_count"] == 3
        assert data_any["items"][1]["student_id"] == "stud_2"
        assert data_any["items"][1]["match_count"] == 1

        # 3. Recruiter match_type=all (Only Alice has all 3 skills)
        res_all = await ac.get(
            f"/recruiter/drives/{drive_id}/matching-students?match_type=all",
            headers={"Authorization": f"Bearer {recruiter_token}"}
        )
        assert res_all.status_code == 200
        data_all = res_all.json()
        assert data_all["total_count"] == 1
        assert data_all["items"][0]["student_id"] == "stud_1"

@pytest.mark.asyncio
async def test_student_recommended_drives_endpoint(monkeypatch):
    """Test GET /drives/recommended for student skill-tailored opportunity feed."""
    import app.routers.drives_student as st_router

    mock_student = {
        "student_id": "stud_1",
        "user_id": "stud_1",
        "full_name": "Alice Sharma",
        "skills": ["Flutter", "Dart", "Firebase"],
    }

    mock_drives = [
        {
            "drive_id": "drive_flutter",
            "company_name": "AppStudio",
            "drive_title": "Mobile Engineer",
            "employment_type": "full_time",
            "location": "Remote",
            "ctc_min": 8.0,
            "ctc_max": 14.0,
            "min_cgpa": 7.0,
            "status": "published",
            "extracted_required_skills": ["Flutter", "Dart", "Firebase", "REST APIs"],
        },
        {
            "drive_id": "drive_python",
            "company_name": "DataCorp",
            "drive_title": "Data Analyst",
            "employment_type": "full_time",
            "location": "Campus",
            "ctc_min": 6.0,
            "ctc_max": 10.0,
            "min_cgpa": 6.5,
            "status": "published",
            "extracted_required_skills": ["Python", "SQL", "Pandas"],
        },
    ]

    async def mock_find_one_student(query):
        return mock_student

    class MockDrivesCursor:
        def sort(self, *args, **kwargs):
            return self
        async def to_list(self, length=None):
            return mock_drives

    def mock_find_drives(query):
        return MockDrivesCursor()

    monkeypatch.setattr(st_router.students_collection, "find_one", mock_find_one_student)
    monkeypatch.setattr(st_router.drives_collection, "find", mock_find_drives)

    student_token = create_access_token("stud_1", "student")
    recruiter_token = create_access_token("rec_1", "recruiter")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # Recruiter forbidden
        res_forbidden = await ac.get(
            "/drives/recommended",
            headers={"Authorization": f"Bearer {recruiter_token}"}
        )
        assert res_forbidden.status_code == 403

        # Student gets recommended drive matching Flutter, Dart, Firebase
        res_rec = await ac.get(
            "/drives/recommended",
            headers={"Authorization": f"Bearer {student_token}"}
        )
        assert res_rec.status_code == 200
        data = res_rec.json()
        assert data["total_count"] == 1
        item = data["items"][0]
        assert item["drive_id"] == "drive_flutter"
        assert item["match_count"] == 3
        assert "Flutter" in item["matched_skills"]
        assert "Dart" in item["matched_skills"]
        assert "Firebase" in item["matched_skills"]
