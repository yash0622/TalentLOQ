import pytest
from io import BytesIO
from fastapi import UploadFile
from app.encryption import encrypt_field, decrypt_field
from app.upload_validator import validate_file_upload, sanitize_filename
from app.middleware import check_ip_in_cidrs
from app.jwt_utils import create_device_token, decode_token

def test_field_level_encryption_decryption():
    original_pii = "John Doe | SSN: 123-45-6789 | CGPA: 9.2"
    ciphertext = encrypt_field(original_pii)
    assert ciphertext != original_pii
    assert len(ciphertext) > 20

    decrypted = decrypt_field(ciphertext)
    assert decrypted == original_pii

def test_sanitize_filename():
    unsafe = "../../../etc/passwd"
    clean = sanitize_filename(unsafe)
    assert ".." not in clean
    assert "/" not in clean

from starlette.datastructures import Headers

def test_validate_file_upload_valid_pdf():
    content = b"%PDF-1.4 mock pdf content"
    mock_file = UploadFile(filename="my_resume.pdf", file=BytesIO(content), headers=Headers({"content-type": "application/pdf"}))
    
    clean_name, content_type = validate_file_upload(mock_file, content)
    assert clean_name == "my_resume.pdf"
    assert content_type == "application/pdf"

def test_validate_file_upload_path_traversal():
    content = b"fake resume"
    mock_file = UploadFile(filename="../malicious.pdf", file=BytesIO(content), headers=Headers({"content-type": "application/pdf"}))
    
    with pytest.raises(Exception) as excinfo:
        validate_file_upload(mock_file, content)
    assert "Path traversal" in str(excinfo.value)

def test_validate_file_upload_invalid_mime():
    content = b"malicious executable binary"
    mock_file = UploadFile(filename="script.exe", file=BytesIO(content), headers=Headers({"content-type": "application/x-msdownload"}))
    
    with pytest.raises(Exception) as excinfo:
        validate_file_upload(mock_file, content)
    assert "Invalid file extension" in str(excinfo.value) or "Invalid MIME type" in str(excinfo.value)

def test_ip_cidr_matching():
    allowed_cidrs = "127.0.0.1, 192.168.1.0/24"
    assert check_ip_in_cidrs("127.0.0.1", allowed_cidrs) is True
    assert check_ip_in_cidrs("192.168.1.55", allowed_cidrs) is True
    assert check_ip_in_cidrs("10.0.0.1", allowed_cidrs) is False

def test_device_binding_token():
    user_id = "user-recruiter-77"
    device_id = "dev-macbook-pro"
    token = create_device_token(user_id, device_id)
    payload = decode_token(token, expected_type="device_verify")
    assert payload["sub"] == user_id
    assert payload["device_id"] == device_id
