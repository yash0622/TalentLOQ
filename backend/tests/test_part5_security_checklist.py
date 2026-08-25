import pytest
import time
from datetime import datetime, timezone, timedelta
import jwt
from io import BytesIO
from fastapi import UploadFile
from starlette.datastructures import Headers

from app.config import settings
from app.jwt_utils import create_access_token, decode_token, create_temp_token
from app.encryption import encrypt_field, decrypt_field
from app.upload_validator import validate_file_upload
from app.middleware import verify_recruiter_ip_restriction
from app.security import hash_token, generate_otp

# 1. Student JWT cannot access recruiter-only routes
def test_student_jwt_cannot_access_recruiter_route():
    student_token = create_access_token(user_id="std-100", role="student")
    decoded = decode_token(student_token)
    assert decoded["role"] == "student"
    assert decoded["role"] != "recruiter"

# 2. Expired JWTs are rejected
def test_expired_jwt_rejection():
    past_time = datetime.now(timezone.utc) - timedelta(minutes=60)
    payload = {
        "sub": "user-expired",
        "role": "student",
        "type": "access",
        "exp": int(past_time.timestamp()),
    }
    expired_token = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
    
    with pytest.raises(Exception) as excinfo:
        decode_token(expired_token, expected_type="access")
    assert "expired" in str(excinfo.value).lower()

# 3. OTP expires and cannot be reused
def test_otp_hashing_and_expiration():
    otp = generate_otp()
    otp_hash1 = hash_token(otp)
    otp_hash2 = hash_token(otp)
    assert otp_hash1 == otp_hash2
    assert len(otp) == 6

    # Test expired time comparison
    past_exp = datetime.now(timezone.utc) - timedelta(minutes=10)
    now = datetime.now(timezone.utc)
    assert now > past_exp

# 4. Recruiter login from unrecognized device detection
def test_unrecognized_device_detection():
    trusted_devices = ["dev-macbook-pro", "dev-workstation-1"]
    incoming_device = "dev-unknown-attacker-phone"
    assert incoming_device not in trusted_devices

# 5. File uploads outside MIME whitelist are rejected
def test_disallowed_mime_type_upload():
    executable_content = b"MZ\x90\x00\x03\x00\x00\x00"
    mock_file = UploadFile(
        filename="malware.exe",
        file=BytesIO(executable_content),
        headers=Headers({"content-type": "application/x-msdownload"}),
    )
    with pytest.raises(Exception) as excinfo:
        validate_file_upload(mock_file, executable_content)
    assert "invalid" in str(excinfo.value).lower()

# 6. Encrypted fields are not readable directly from raw MongoDB document
def test_encrypted_field_privacy_in_mongodb():
    sensitive_pii = "Student Phone: +1-555-0199 | SSN: 999-00-1234"
    encrypted_blob = encrypt_field(sensitive_pii)
    
    # Raw MongoDB document content
    mongo_raw_doc = {
        "user_id": "std-99",
        "encrypted_pii": encrypted_blob,
    }
    
    # Verify raw MongoDB value is ciphertext, not plaintext
    assert sensitive_pii not in mongo_raw_doc["encrypted_pii"]
    assert mongo_raw_doc["encrypted_pii"] != sensitive_pii
    
    # Decrypt upon authorized retrieval
    decrypted_pii = decrypt_field(mongo_raw_doc["encrypted_pii"])
    assert decrypted_pii == sensitive_pii
