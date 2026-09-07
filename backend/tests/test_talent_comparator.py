import pytest
from app.services.talent_comparator import TalentComparatorService

def test_deployment_scoring():
    # Candidate with Docker + AWS + Linux
    skills = ["python", "docker", "aws", "linux"]
    score, detected = TalentComparatorService.compute_deployment_score(skills)
    assert score == 100.0  # Containers (35) + Cloud (35) + CI/CD/Hosting (30)
    assert "Docker" in detected
    assert "AWS" in detected
    assert "Linux" in detected

    # Candidate with only Docker
    score_docker, detected_docker = TalentComparatorService.compute_deployment_score(["docker", "python"])
    assert score_docker == 35.0
    assert detected_docker == ["Docker"]

    # Candidate with no deployment skills
    score_none, detected_none = TalentComparatorService.compute_deployment_score(["python", "html"])
    assert score_none == 0.0
    assert detected_none == []


def test_internship_scoring():
    assert TalentComparatorService.compute_internship_score(0) == 0.0
    assert TalentComparatorService.compute_internship_score(1) == 65.0
    assert TalentComparatorService.compute_internship_score(2) == 85.0
    assert TalentComparatorService.compute_internship_score(3) == 100.0
    assert TalentComparatorService.compute_internship_score(5) == 100.0


def test_rank_candidates_sorting():
    required_skills = ["python", "fastapi", "docker", "postgresql"]

    student_a = {
        "student_id": "std_1",
        "full_name": "Alice High Experience",
        "skills": ["python", "fastapi", "docker", "postgresql", "aws", "ci/cd"],
        "deployment_skills": ["Docker", "AWS", "CI/CD"],
        "internship_count": 2,
        "cgpa": 8.5
    }

    student_b = {
        "student_id": "std_2",
        "full_name": "Bob Fresher",
        "skills": ["python", "fastapi"],
        "deployment_skills": [],
        "internship_count": 0,
        "cgpa": 9.2
    }

    ranked = TalentComparatorService.rank_candidates([student_b, student_a], required_skills)

    assert len(ranked) == 2
    # Alice should be Rank 1 due to high skill match (100%), deployment (100%), and 2 internships (85%)
    assert ranked[0]["student_id"] == "std_1"
    assert ranked[0]["rank"] == 1
    assert ranked[1]["student_id"] == "std_2"
    assert ranked[1]["rank"] == 2
    assert ranked[0]["composite_score"] > ranked[1]["composite_score"]
