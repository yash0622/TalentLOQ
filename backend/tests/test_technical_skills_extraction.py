"""
Comprehensive test suite verifying that:
1. Only technical skills are extracted from resumes (soft skills and spoken languages strictly isolated).
2. The entire resume text is read and processed without truncation (sliding window chunking).
3. Resume words are extracted and technical skills identified offline (zero external LLM APIs).
4. Student profile receives strictly technical skills in both 'skills' and 'technical_skills'.
"""
import pytest
from unittest.mock import AsyncMock, MagicMock
from app.services.skill_matcher import (
    skill_matcher_engine,
    is_soft_skill,
    is_technical_skill,
    is_spoken_language,
)
from app.document_detection.parsers import ResumeParser


def test_soft_skills_and_spoken_languages_detection():
    """Verify helpers correctly identify soft skills, spoken languages, and technical skills."""
    assert is_soft_skill("Communication Skills") is True
    assert is_soft_skill("Leadership") is True
    assert is_soft_skill("Teamwork") is True
    assert is_soft_skill("Problem Solving") is True
    assert is_soft_skill("Critical Thinking") is True
    assert is_soft_skill("Time Management") is True

    assert is_spoken_language("English") is True
    assert is_spoken_language("Hindi") is True
    assert is_spoken_language("Gujarati") is True
    assert is_spoken_language("French") is True

    assert is_technical_skill("Python") is True
    assert is_technical_skill("FastAPI") is True
    assert is_technical_skill("Docker") is True
    assert is_technical_skill("Flutter") is True
    assert is_technical_skill("MongoDB") is True
    assert is_technical_skill("Communication Skills") is False
    assert is_technical_skill("English") is False


def test_extract_skills_from_text_technical_only():
    """Verify extract_skills_from_text filters out soft skills when technical_only is True."""
    mixed_text = """
    Candidate has excellent Communication Skills, strong Leadership, and Teamwork abilities.
    Proficient in Python, FastAPI, Docker, and PostgreSQL with experience in Problem Solving.
    Spoken languages include English and Hindi.
    """
    tech_skills = skill_matcher_engine.extract_skills_from_text(mixed_text, use_ner=False, technical_only=True)
    assert "Python" in tech_skills
    assert "FastAPI" in tech_skills
    assert "Docker" in tech_skills
    assert "PostgreSQL" in tech_skills
    assert "Communication Skills" not in tech_skills
    assert "Leadership" not in tech_skills
    assert "Teamwork" not in tech_skills
    assert "Problem Solving" not in tech_skills
    assert "English" not in tech_skills


def test_read_whole_resume_sliding_window():
    """
    Verify that technical skills located at the bottom of a large resume (> 3000 chars)
    are fully extracted and not truncated.
    """
    filler = "This is detailed project documentation and experience history. " * 70  # ~4400 characters
    long_resume = f"""
    John Developer
    john@example.com | Vadodara, India

    SUMMARY
    {filler}

    LATE CERTIFICATIONS AND ARCHITECTURAL SKILLS (AT END OF RESUME)
    Kubernetes, PyTorch, GraphQL, Redis, Rust
    """
    assert len(long_resume) > 4000

    extracted = skill_matcher_engine.extract_skills_from_text(long_resume, use_ner=False, technical_only=True)
    assert "Kubernetes" in extracted
    assert "PyTorch" in extracted
    assert "GraphQL" in extracted
    assert "Redis" in extracted
    assert "Rust" in extracted


def test_resume_parser_populates_only_technical_skills():
    """Verify ResumeParser outputs strictly technical skills into 'skills' and 'technical_skills'."""
    resume_text = """
    CHINTAN SHARMA
    Vadodara, Gujarat | +91 8238089207 | student@gsfcuniversity.ac.in
    github.com/chintan | linkedin.com/in/chintan

    TECHNICAL SKILLS
    Programming Languages: Python, Dart, JavaScript, TypeScript, C++
    Frameworks: Flutter, FastAPI, Django, React
    Databases & Cloud: MongoDB, PostgreSQL, Docker, AWS, Git

    SOFT SKILLS
    Communication Skills, Leadership, Team Collaboration, Problem Solving, Critical Thinking

    LANGUAGES
    English, Hindi, Gujarati
    """
    result = ResumeParser.parse(resume_text)

    # Technical skills verification
    for tech in ["Python", "Dart", "Flutter", "FastAPI", "MongoDB", "Docker", "Git", "React"]:
        assert tech in result["technical_skills"]
        assert tech in result["skills"]

    # Verify NO soft skills in skills or technical_skills
    for soft in ["Communication Skills", "Communication", "Leadership", "Teamwork", "Problem Solving", "Critical Thinking"]:
        assert soft not in result["skills"]
        assert soft not in result["technical_skills"]

    # Verify NO spoken languages in skills or technical_skills
    for lang in ["English", "Hindi", "Gujarati"]:
        assert lang not in result["skills"]
        assert lang not in result["technical_skills"]
        assert lang in result["languages"]

    # Verify soft skills isolated in soft_skills
    assert "Problem Solving" in result["soft_skills"]
    assert "Communication" in result["soft_skills"] or "Communication Skills" in result["soft_skills"]


@pytest.mark.asyncio
async def test_auth_upload_resume_profile_update(monkeypatch):
    """
    Verifies that uploading a resume saves strictly technical skills into both
    'skills' and 'technical_skills' fields in the student document.
    """
    from app.routers.auth import upload_resume
    from fastapi import UploadFile
    import io

    resume_content = b"""
    Candidate Name: Rohan Verma
    Email: rohan@test.com
    Phone: 9876543210
    Technical Skills: Python, FastAPI, Docker, Kubernetes, Flutter
    Soft Skills: Public Speaking, Teamwork, Leadership
    Spoken Languages: English, Hindi
    """

    mock_updated_data = {}

    class MockStudentsCollection:
        async def update_many(self, query, update):
            mock_updated_data.update(update.get("$set", {}))
            return MagicMock(modified_count=1)

        async def update_one(self, query, update):
            mock_updated_data.update(update.get("$set", {}))
            return MagicMock(modified_count=1)

    class MockGridFS:
        async def upload_from_stream(self, name, stream, metadata=None):
            return "mock_grid_id_123"

    monkeypatch.setattr("app.routers.auth.students_collection", MockStudentsCollection())
    monkeypatch.setattr("app.routers.auth.get_grid_fs", lambda: MockGridFS())

    upload_file = UploadFile(
        file=io.BytesIO(resume_content),
        filename="rohan_resume.pdf",
        headers={"content-type": "application/pdf"}
    )

    async def mock_extract(contents, filename):
        return resume_content.decode("utf-8"), None

    class MockClassification:
        is_resume = True
        confidence = 0.95
        error = None
        def to_dict(self):
            return {"document_type": "RESUME", "confidence": 0.95}

    monkeypatch.setattr("app.routers.auth.extract_document_text", mock_extract)
    monkeypatch.setattr("app.routers.auth.classify_document", lambda text, filename: MockClassification())

    response = await upload_resume(file=upload_file, credentials=None)
    assert response["has_resume"] is True

    assert "skills" in mock_updated_data
    assert "technical_skills" in mock_updated_data
    assert mock_updated_data["skills"] == mock_updated_data["technical_skills"]

    # Check that technical skills exist
    assert "Python" in mock_updated_data["technical_skills"]
    assert "FastAPI" in mock_updated_data["technical_skills"]
    assert "Docker" in mock_updated_data["technical_skills"]

    # Check that soft skills are NOT in technical_skills or skills
    assert "Teamwork" not in mock_updated_data["technical_skills"]
    assert "Leadership" not in mock_updated_data["technical_skills"]
    assert "Public Speaking" not in mock_updated_data["technical_skills"]
    assert "Teamwork" not in mock_updated_data["skills"]
    assert "Leadership" not in mock_updated_data["skills"]
