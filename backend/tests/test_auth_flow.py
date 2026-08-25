import pytest
import time
from datetime import datetime, timezone
from app.config import settings, determine_role
from app.security import (
    hash_password,
    verify_password,
    sanitize_text,
    verify_captcha,
    generate_otp,
    hash_token,
)
from app.jwt_utils import (
    create_access_token,
    create_refresh_token,
    create_temp_token,
    decode_token,
)

def test_password_hashing_and_verification():
    raw_pwd = "SuperSecretPassword123!"
    hashed = hash_password(raw_pwd)
    assert hashed != raw_pwd
    assert verify_password(raw_pwd, hashed) is True
    assert verify_password("WrongPassword", hashed) is False

def test_sanitize_text():
    dirty = "Hello <script>alert('xss')</script><b>World</b>\x00\x07!"
    clean = sanitize_text(dirty)
    assert "<script>" not in clean
    assert "<b>" not in clean
    assert "Hello World!" in clean

def test_generate_otp():
    otp = generate_otp()
    assert len(otp) == 6
    assert otp.isdigit()

def test_hash_token():
    token = "sample-token-string"
    h1 = hash_token(token)
    h2 = hash_token(token)
    assert h1 == h2
    assert len(h1) == 64

def test_jwt_access_token():
    user_id = "usr-12345"
    token = create_access_token(user_id=user_id, role="student", auth_time=1700000000)
    decoded = decode_token(token, expected_type="access")
    assert decoded["sub"] == user_id
    assert decoded["role"] == "student"
    assert decoded["type"] == "access"
    assert decoded["auth_time"] == 1700000000

def test_jwt_temp_otp_token():
    user_id = "usr-recruiter-99"
    token = create_temp_token(user_id=user_id)
    decoded = decode_token(token, expected_type="temp_otp")
    assert decoded["sub"] == user_id
    assert decoded["role"] == "recruiter"
    assert decoded["type"] == "temp_otp"

def test_jwt_refresh_token():
    user_id = "usr-refresh-1"
    token_str, token_id = create_refresh_token(user_id=user_id, role="student")
    decoded = decode_token(token_str, expected_type="refresh")
    assert decoded["sub"] == user_id
    assert decoded["token_id"] == token_id
    assert decoded["type"] == "refresh"

def test_verify_captcha():
    assert verify_captcha("valid-captcha-token-12345") is True
    assert verify_captcha("") is False
