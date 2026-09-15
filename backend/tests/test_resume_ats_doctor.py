import pytest
from app.services.resume_ats_doctor import ResumeAtsDoctor

def test_resume_ats_doctor_high_match():
    resume_text = """
    John Doe
    john.doe@example.com | (555) 123-4567

    Education
    B.Tech Computer Science 2020-2024

    Skills
    Python, FastAPI, Docker, PostgreSQL, AWS

    Experience
    - Developed scalable REST APIs using Python and FastAPI.
    - Deployed Docker containers to AWS ECS, reducing server costs by 30%.
    - Optimized database queries in PostgreSQL, accelerating response time by 45%.

    Projects
    - Architected asynchronous API gateway handling 10k+ requests/sec.
    """
    student_skills = ["Python", "FastAPI", "Docker", "PostgreSQL", "AWS"]
    projects = [
        {
            "title": "Cloud API Gateway",
            "description": "Architected asynchronous API gateway handling 10k+ requests/sec.",
        }
    ]
    drive_doc = {
        "drive_title": "Backend Python Engineer",
        "required_skills": ["Python", "FastAPI", "Docker"],
        "description": "We are seeking a Python and FastAPI engineer with Docker container experience.",
    }

    result = ResumeAtsDoctor.analyze_resume_fit(
        resume_text=resume_text,
        student_skills=student_skills,
        projects=projects,
        drive_doc=drive_doc,
    )

    assert result["ats_score"] >= 80
    assert result["fit_tier"] == "EXCELLENT MATCH"
    assert "Python" in result["matched_skills"]
    assert "FastAPI" in result["matched_skills"]
    assert "Docker" in result["matched_skills"]
    assert result["missing_skills"] == []
    assert result["has_quantifiable_metrics"] is True
    assert result["metric_count"] >= 2
    assert len(result["bullet_action_verbs"]) >= 3
    assert result["format_health"]["format_score"] == 100
    assert result["format_health"]["has_contact_info"] is True
    assert result["format_health"]["has_layout_risk"] is False


def test_resume_ats_doctor_no_false_positive_metrics():
    """
    Asserts that bare 2+ digit numbers like graduation years (2023-2027),
    CGPA 10, or phone numbers do NOT falsely trigger quantifiable metrics.
    """
    resume_text = """
    Jane Smith
    jane@example.com | (555) 987-6543

    Education
    B.Tech 2023-2027 with CGPA 10 out of 10.
    Batch of 2024.

    Skills
    Python, Git

    Experience
    Worked on software team.
    Assisted in writing documentation.

    Projects
    Personal website created for portfolio.
    """
    student_skills = ["Python", "Git"]
    projects = [
        {
            "title": "Portfolio",
            "description": "Created portfolio website in year 2024.",
        }
    ]
    drive_doc = {
        "drive_title": "Software Developer",
        "required_skills": ["Python", "Git"],
        "description": "Looking for Python and Git developer.",
    }

    result = ResumeAtsDoctor.analyze_resume_fit(
        resume_text=resume_text,
        student_skills=student_skills,
        projects=projects,
        drive_doc=drive_doc,
    )

    # Bare numbers 2023, 2027, 10, 2024, phone number should NOT count as metrics
    assert result["has_quantifiable_metrics"] is False
    assert result["metric_count"] == 0
    assert any("Quantify your achievements" in s for s in result["suggestions"])


def test_resume_ats_doctor_format_health_warnings():
    """
    Asserts that missing headers, trapped contact info, and multi-column tables
    are flagged with format warnings.
    """
    scrambled_resume = """
    Software Developer Profile
    Profile Summary    Company Name    Role Details    Dates Active
    Did frontend work    Acme Corp       React Developer 2022-2023
    Did backend work     Beta LLC        Node Engineer   2023-2024
    Database work        Gamma Inc       SQL Admin       2024-2025
    Cloud operations     Delta Ltd       DevOps Intern   2025-2026
    """
    format_health = ResumeAtsDoctor.check_format_health(scrambled_resume)

    assert format_health["format_score"] < 50
    assert format_health["has_contact_info"] is False
    assert format_health["has_layout_risk"] is True
    assert any("Missing standard 'Education'" in w for w in format_health["format_warnings"])
    assert any("Multi-column layout" in w for w in format_health["format_warnings"])
    assert any("No email address detected" in w for w in format_health["format_warnings"])


def test_resume_ats_doctor_keyword_gaps():
    resume_text = """
    Junior Developer familiar with HTML, CSS, and basic JavaScript.
    Built simple static portfolio website.
    """
    student_skills = ["HTML", "CSS", "JavaScript"]
    projects = []
    drive_doc = {
        "drive_title": "Full Stack Engineer",
        "required_skills": ["React", "Node.js", "MongoDB", "Docker", "TypeScript"],
        "description": "Looking for React and Node.js developer with Docker experience.",
    }

    result = ResumeAtsDoctor.analyze_resume_fit(
        resume_text=resume_text,
        student_skills=student_skills,
        projects=projects,
        drive_doc=drive_doc,
    )

    assert result["ats_score"] < 60
    assert result["fit_tier"] in ["MODERATE MATCH", "NEEDS OPTIMIZATION"]
    assert len(result["missing_skills"]) > 0
    assert any("Add missing keywords" in s for s in result["suggestions"])


def test_academic_projects_not_classified_as_education():
    """
    Asserts that an 'Academic Projects' header is detected as Projects
    and does NOT falsely satisfy the 'Education' section requirement.
    """
    resume_text = """
    Alex Green
    alex@example.com | (555) 321-7654

    Skills
    Python, Django

    Academic Projects
    - Built internal tooling dashboard.

    Experience
    - Maintained backend microservices.
    """
    format_health = ResumeAtsDoctor.check_format_health(resume_text)

    assert "Projects" in format_health["sections_detected"]
    assert "Education" not in format_health["sections_detected"]
    assert any("Missing standard 'Education'" in w for w in format_health["format_warnings"])


def test_right_aligned_dates_do_not_trigger_layout_risk():
    """
    Asserts that a standard single-column resume with right-aligned dates
    across multiple entries is NOT falsely penalized for multi-column layout risk.
    """
    resume_text = """
    Jane Doe
    jane.doe@example.com | (555) 999-1111

    Education
    B.Tech Computer Science                                        2021 - 2025

    Skills
    Python, Docker, Kubernetes

    Experience
    Software Engineering Intern, RedSpark                         Jun 2024 - Aug 2024
    Backend Developer, Alpha Labs                                 Jan 2024 - Apr 2024
    Open Source Contributor, Python Org                           Sep 2023 - Dec 2023
    Research Assistant, GSFC University                           Jan 2023 - May 2023

    Projects
    Distributed Task Queue                                         Oct 2024 - Present
    """
    format_health = ResumeAtsDoctor.check_format_health(resume_text)

    # Despite 6 lines with wide whitespace gaps, all right sides are dates/durations
    assert format_health["has_layout_risk"] is False
    assert not any("Multi-column layout" in w for w in format_health["format_warnings"])
    assert format_health["format_score"] == 100


def test_latency_seconds_and_markdown_bold_bullets():
    """
    Asserts that latency wins in seconds ('reduced latency by 2s') count as quantifiable metrics,
    and markdown bold bullets ('* **Built** system') correctly match bullet-start action verbs.
    """
    resume_text = """
    Chris Ray
    chris@example.com | (555) 777-8888

    Education
    Academics
    B.Tech in Information Technology

    Skills
    Go, Redis, Kubernetes

    Experience
    * **Built** distributed caching layer that reduced query latency by 2s.
    - **Optimized** payload compression, cutting payload transfer time by 500ms.
    * **Architected** microservice gateway handling 50k+ daily transactions.

    Projects
    * **Deployed** production clusters on AWS.
    """
    drive_doc = {
        "drive_title": "Systems Engineer",
        "required_skills": ["Go", "Redis"],
        "description": "Looking for Go and Redis engineer.",
    }

    result = ResumeAtsDoctor.analyze_resume_fit(
        resume_text=resume_text,
        student_skills=["Go", "Redis"],
        projects=[],
        drive_doc=drive_doc,
    )

    assert result["has_quantifiable_metrics"] is True
    assert result["metric_count"] >= 2
    assert "built" in result["bullet_action_verbs"]
    assert "optimized" in result["bullet_action_verbs"]
    assert "architected" in result["bullet_action_verbs"]
    assert result["ats_score"] >= 80

