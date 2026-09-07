from app.document_detection.parsers import ResumeParser

def test_resume_parser_internship_extraction():
    sample_resume_text = """
    JOHN DOE
    john.doe@example.com | +91 9876543210
    Vadodara, Gujarat

    PROFESSIONAL SUMMARY
    Passionate Backend Engineer with experience in Python, FastAPI, Docker, and AWS.

    TECHNICAL SKILLS
    Languages: Python, JavaScript, C++, Dart, SQL
    Cloud & DevOps: Docker, Kubernetes, AWS, CI/CD, Linux, Nginx
    Databases: MongoDB, PostgreSQL, Redis

    WORK EXPERIENCE & INTERNSHIPS
    Backend Engineering Intern at Acme Technologies (May 2024 - Jul 2024)
    - Developed scalable microservices using FastAPI and MongoDB.
    - Containerized applications with Docker and deployed to AWS EC2.

    Full Stack Web Intern at Innovate Labs (Dec 2023 - Feb 2024)
    - Built responsive web dashboards using React and Node.js.
    - Set up automated CI/CD pipelines with GitHub Actions.

    EDUCATION
    B.Tech in Computer Science & Engineering - GSFC University (2021 - 2025)
    CGPA: 8.85 / 10.0
    """

    parsed = ResumeParser.parse(sample_resume_text)

    # Verify technical skills
    assert "Python" in parsed["technical_skills"]
    assert "FastAPI" in parsed["technical_skills"]

    # Verify deployment skills
    assert "Docker" in parsed["deployment_skills"]
    assert "AWS" in parsed["deployment_skills"]
    assert "Linux" in parsed["deployment_skills"]
    assert "CI/CD" in parsed["deployment_skills"]

    # Verify internships extracted
    assert parsed["internship_count"] >= 2
    assert len(parsed["internships"]) >= 2

    comp_names = [i["company_name"].lower() for i in parsed["internships"]]
    assert any("acme" in c for c in comp_names)
    assert any("innovate" in c for c in comp_names)
