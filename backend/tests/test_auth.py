import pytest
from app.config import settings, determine_role, RESERVED_EMAILS
from app.models import UserModel, StudentModel, AuditLogModel, StudentRegisterRequest

def test_determine_role_recruiter():
    assert determine_role("telentloqrecruiter@gmail.com") == "recruiter"
    assert determine_role("TELENTLOQRECRUITER@GMAIL.COM") == "recruiter"

def test_determine_role_student():
    assert determine_role("student@university.edu") == "student"
    assert determine_role("john.doe@gmail.com") == "student"

def test_reserved_emails_set():
    assert settings.RECRUITER_EMAIL in RESERVED_EMAILS
    assert "telentloqrecruiter@gmail.com" in RESERVED_EMAILS

def test_user_model_instantiation():
    user = UserModel(
        email="student@university.edu",
        password_hash="hashedpwd123",
        role="student",
        is_verified=False,
        must_change_password=False,
    )
    assert user.role == "student"
    assert user.is_verified is False
    assert user.must_change_password is False
    assert isinstance(user.trusted_devices, list)

def test_student_model_instantiation():
    student = StudentModel(
        user_id="user-123",
        education="B.Tech Computer Science",
        CGPA=8.75,
        skills=["Python", "Flutter", "MongoDB"],
    )
    assert student.user_id == "user-123"
    assert student.CGPA == 8.75
    assert len(student.skills) == 3

def test_audit_log_model_instantiation():
    log = AuditLogModel(
        user_id="user-123",
        action="LOGIN",
        ip="192.168.1.1",
        device="Mozilla/5.0",
    )
    assert log.action == "LOGIN"
    assert log.ip == "192.168.1.1"

def test_student_register_request_reserved_email_check():
    req = StudentRegisterRequest(
        email="telentloqrecruiter@gmail.com",
        password="Password123!",
        education="B.Tech CS",
        CGPA=8.0,
        skills=["Python"]
    )
    assert req.email.lower() in RESERVED_EMAILS
