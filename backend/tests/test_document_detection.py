"""
Comprehensive Test Suite for Document Type Detection System.
Validates classification accuracy, confidence scoring, edge case handling,
and API integration endpoints.
"""
import pytest
import httpx
from httpx import AsyncClient
from app.main import app
from app.document_detection import (
    extract_document_text,
    classify_document,
    DocumentTypeEnum,
    RESUME_CONFIDENCE_THRESHOLD,
)


@pytest.mark.asyncio
async def test_valid_professional_resume():
    text = """
    John Doe
    Senior Software Engineer | San Francisco, CA | john.doe@email.com | +1 555-019-2834 | linkedin.com/in/johndoe

    PROFESSIONAL SUMMARY
    Results-driven Senior Software Engineer with 8+ years of experience designing and building scalable cloud microservices.

    WORK EXPERIENCE
    Lead Backend Engineer | Tech Corp | 2021 - Present
    - Architected distributed REST APIs handling 50k requests per second using Python and FastAPI.
    - Led a team of 6 engineers to optimize database queries, reducing response latency by 35%.

    Software Engineer | Data Solutions | 2017 - 2021
    - Developed automated CI/CD deployment pipelines using Docker and AWS.

    EDUCATION
    Master of Science in Computer Science | Stanford University (2015 - 2017) | CGPA: 3.9/4.0
    Bachelor of Technology in Computer Science | GSFC University (2011 - 2015)

    TECHNICAL SKILLS
    Languages: Python, Go, Java, TypeScript, SQL
    Frameworks: FastAPI, Django, Flutter, React
    Tools: Docker, Kubernetes, AWS, Git, MongoDB
    """
    res = classify_document(text, "john_doe_resume.pdf")
    assert res.is_resume is True
    assert res.document_type == DocumentTypeEnum.RESUME
    assert res.confidence >= 0.70
    assert "Education" in res.detected_sections
    assert "Work Experience" in res.detected_sections
    assert "Contact Information" in res.detected_sections


@pytest.mark.asyncio
async def test_student_resume():
    text = """
    Chintan Sharma
    Student Candidate | 24bt04d231@gsfcuniversity.ac.in | +91 9876543210 | github.com/chintansharma

    CAREER OBJECTIVE
    Enthusiastic B.Tech Computer Science student seeking software development engineering internship.

    EDUCATION
    B.Tech Computer Science Engineering | GSFC University | 2022 - 2026 | CGPA: 9.9 / 10.0
    High School Diploma | Science Stream | 2022

    ACADEMIC PROJECTS
    Placement Portal Web App
    - Built mobile portal in Flutter and Python FastAPI with MongoDB database.
    - Implemented secure JWT authentication and audit log telemetry.

    TECHNICAL SKILLS
    Flutter, Dart, Python, FastAPI, MongoDB, Git, HTML/CSS
    """
    res = classify_document(text, "chintan_student_cv.pdf")
    assert res.is_resume is True
    assert res.document_type == DocumentTypeEnum.RESUME
    assert res.confidence >= 0.70


@pytest.mark.asyncio
async def test_fresher_resume():
    text = """
    Priya Patel
    priya.patel@gmail.com | +91 9123456789 | Vadodara, India

    PROFESSIONAL SUMMARY
    Recent Information Technology graduate with strong foundation in algorithm design and database management.

    EDUCATION
    Bachelor of Engineering in IT | Parul University | 2020 - 2024 | CGPA: 8.5 / 10.0

    INTERNSHIPS & EXPERIENCE
    Frontend Developer Intern | WebStudio Pvt Ltd | Jan 2024 - May 2024
    - Developed responsive web interfaces using HTML, CSS, JavaScript, and React.

    PROJECTS
    Online E-Commerce Application
    - Created REST API backend using Python and SQLite database.

    TECHNICAL SKILLS
    C++, Python, JavaScript, React, SQL, Git
    """
    res = classify_document(text, "fresher_resume_priya.docx")
    assert res.is_resume is True
    assert res.confidence >= 0.70


@pytest.mark.asyncio
async def test_technical_resume():
    text = """
    Alex Rivera - DevOps & Cloud Infrastructure Engineer
    alex.rivera@cloudtech.io | +1 415-555-9012 | github.com/arivera | linkedin.com/in/arivera

    SUMMARY
    Certified AWS Solutions Architect with expertise in infrastructure as code, Kubernetes orchestration, and site reliability engineering.

    WORK HISTORY
    Site Reliability Engineer | CloudScale Inc | 2020 - Present
    - Managed Kubernetes clusters across multi-cloud environments.
    - Automated deployment pipelines using Terraform and Ansible.

    EDUCATION
    B.S. Information Systems | University of California | CGPA 3.7

    TECHNICAL SKILLS & CERTIFICATIONS
    Certifications: AWS Certified Solutions Architect, Certified Kubernetes Administrator (CKA)
    Skills: Terraform, Ansible, Docker, Kubernetes, AWS, Prometheus, Python, Bash
    """
    res = classify_document(text, "alex_rivera_cv.pdf")
    assert res.is_resume is True
    assert res.document_type == DocumentTypeEnum.RESUME


@pytest.mark.asyncio
async def test_academic_assignment_rejection():
    text = """
    GSFC University - Department of Computer Science
    Course Code: CS304 - Database Management Systems
    Assignment 1: Relational Algebra & SQL Normalization

    Student Name: Roll No 45
    Deadline: October 15, 2026

    Question 1: Explain 3NF normalization with an example table schema.
    Question 2: Write SQL queries to perform inner join between Students and Courses tables.

    Submission Instructions: Upload PDF file to the university portal. Late submission penalty 10%.
    """
    res = classify_document(text, "assignment_1_sql.pdf")
    assert res.is_resume is False
    assert res.document_type in (DocumentTypeEnum.OTHER_DOCUMENT, DocumentTypeEnum.UNCERTAIN)
    assert res.confidence < RESUME_CONFIDENCE_THRESHOLD


@pytest.mark.asyncio
async def test_research_paper_rejection():
    text = """
    Deep Learning Approaches for Automated Document Classification
    IEEE Transactions on Neural Networks and Learning Systems
    Abstract:
    In this research paper, we propose a novel transformer-based neural network architecture for document classification.
    Our empirical results demonstrate a 98.4% F1-score on benchmark datasets.

    1. Introduction
    Recent advances in natural language processing (NLP) have revolutionized text analysis...

    2. Related Work
    Previous studies by Smith et al. focused on SVM classifiers...

    References:
    [1] IEEE Journal of Machine Learning, Vol 14, doi:10.1109/TNNLS.2024.12345
    [2] ArXiv preprint arXiv:2401.00123
    """
    res = classify_document(text, "research_paper_ieee.pdf")
    assert res.is_resume is False
    assert res.document_type == DocumentTypeEnum.OTHER_DOCUMENT
    assert res.confidence < RESUME_CONFIDENCE_THRESHOLD


@pytest.mark.asyncio
async def test_invoice_billing_rejection():
    text = """
    INVOICE #INV-2026-9821
    TechSupply Solutions LLC
    123 Logistics Way, Commerce City

    Bill To: Global Tech Inc
    Billing Address: 456 Enterprise Blvd
    Invoice Date: August 10, 2026
    Payment Terms: Net 30

    Description               Qty     Unit Price     Subtotal
    Cloud Server Hosting       1      $450.00        $450.00
    SSL Certificate License    2      $50.00         $100.00

    Subtotal: $550.00
    Tax Rate: 8.0%
    Total Due: $594.00
    Amount Payable: $594.00
    """
    res = classify_document(text, "invoice_server_billing.pdf")
    assert res.is_resume is False
    assert res.document_type == DocumentTypeEnum.OTHER_DOCUMENT
    assert res.confidence < RESUME_CONFIDENCE_THRESHOLD


@pytest.mark.asyncio
async def test_certificate_only_rejection():
    text = """
    CERTIFICATE OF COMPLETION
    This is to certify that
    Candidate Name
    has successfully completed the 2-hour online workshop on
    Introduction to Web Accessibility
    Issued on August 1, 2026
    Authorized Signature: Dr. A. Kumar
    """
    res = classify_document(text, "workshop_certificate.pdf")
    assert res.is_resume is False
    assert res.confidence < RESUME_CONFIDENCE_THRESHOLD


@pytest.mark.asyncio
async def test_random_text_rejection():
    text = """
    The quick brown fox jumps over the lazy dog.
    Lorem ipsum dolor sit amet, consectetur adipiscing elit.
    This is a random text document containing no structured resume or career information.
    """
    res = classify_document(text, "random_notes.txt")
    assert res.is_resume is False
    assert res.document_type == DocumentTypeEnum.OTHER_DOCUMENT


@pytest.mark.asyncio
async def test_empty_document_handling():
    res = classify_document("", "empty.pdf")
    assert res.is_resume is False
    assert res.confidence == 0.0
    assert res.error is not None


@pytest.mark.asyncio
async def test_corrupted_document_handling():
    corrupted_bytes = b"NOT_A_REAL_PDF_STREAM_CORRUPTED_DATA_12345"
    text, error = await extract_document_text(corrupted_bytes, "corrupted.pdf")
    # Should handle gracefully without throwing uncaught exceptions
    res = classify_document(text, "corrupted.pdf")
    assert res.is_resume is False


@pytest.mark.asyncio
async def test_unusual_formatting_resume():
    text = """
    SARAH JENKINS - SOFTWARE DEVELOPER
    Email: s.jenkins@dev.net | Cell: 555-432-8765 | GitHub: github.com/sjenkins

    CAREER HISTORY:
    * Lead Software Engineer (2021 to Present) at FinTech Systems
    - Designed microservice architecture handling millions of transactions daily.
    - Skills used: Python, Java, PostgreSQL, Redis, Docker

    EDUCATIONAL BACKGROUND:
    B.S. Software Engineering, Graduated 2020. Cumulative GPA: 3.8

    COMPETENCIES & TOOLS:
    Python, FastAPI, Java, React, Microservices, Git, Docker, Kubernetes
    """
    res = classify_document(text, "sarah_resume_custom_format.txt")
    assert res.is_resume is True
    assert res.confidence >= 0.70


@pytest.mark.asyncio
async def test_upload_resume_api_integration_resume_passes():
    resume_text = """
    Jane Smith
    jane.smith@email.com | +1 555-123-4567 | github.com/janesmith

    SUMMARY
    Full Stack Developer with 4 years of experience building web applications.

    EDUCATION
    B.Tech Computer Science Engineering | GSFC University | 2020 - 2024 | CGPA: 8.8 / 10.0

    WORK EXPERIENCE
    Software Developer | Web Corp | 2022 - Present
    - Developed backend APIs using Python FastAPI and MongoDB.

    TECHNICAL SKILLS
    Python, FastAPI, Flutter, JavaScript, HTML, CSS, Git, MongoDB
    """
    files = {
        "file": ("jane_smith_resume.txt", resume_text.encode("utf-8"), "text/plain")
    }

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.post("/auth/upload-resume", files=files)

    assert response.status_code == 200
    data = response.json()
    assert data["has_resume"] is True
    assert "document_classification" in data
    assert data["document_classification"]["is_resume"] is True
    assert data["document_classification"]["document_type"] == "RESUME"


@pytest.mark.asyncio
async def test_upload_resume_api_integration_non_resume_fails():
    invoice_text = """
    INVOICE #10293
    Total Due: $450.00
    Amount Payable: $450.00
    Invoice Date: 2026-08-15
    Payment Terms: Due upon receipt
    Subtotal: $450.00
    Tax Rate: 0%
    Billing Address: 123 Main Street
    """
    files = {
        "file": ("invoice_document.txt", invoice_text.encode("utf-8"), "text/plain")
    }

    async with AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.post("/auth/upload-resume", files=files)

    assert response.status_code == 400
    data = response.json()
    assert "detail" in data
    detail = data["detail"]
    assert "document_classification" in detail
    assert detail["document_classification"]["is_resume"] is False
