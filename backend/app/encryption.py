import os
import logging
from cryptography.fernet import Fernet
from app.config import settings

logger = logging.getLogger("talentloq.encryption")

# Load Field Encryption Key from environment, or generate a stable default for dev
raw_key = os.environ.get("FIELD_ENCRYPTION_KEY")
if not raw_key:
    # Deterministic Fernet key derived for dev environment if not supplied
    import base64, hashlib
    default_secret = settings.JWT_SECRET + "_field_encryption_key_salt"
    derived = hashlib.sha256(default_secret.encode()).digest()
    raw_key = base64.urlsafe_b64encode(derived).decode()

try:
    fernet = Fernet(raw_key.encode('utf-8'))
except Exception as e:
    logger.error(f"Invalid FIELD_ENCRYPTION_KEY provided: {e}")
    # Fallback to key generation
    generated_key = Fernet.generate_key()
    fernet = Fernet(generated_key)
    logger.warning("Generated temporary Fernet key for field encryption.")

def encrypt_field(plaintext: str) -> str:
    """
    Field-level AES encryption (via Fernet / AES-128-CBC + HMAC-SHA256).
    Applies encryption before storing PII or confidential documents into MongoDB.
    """
    if not plaintext:
        return ""
    encrypted_bytes = fernet.encrypt(plaintext.encode('utf-8'))
    return encrypted_bytes.decode('utf-8')

def decrypt_field(ciphertext: str) -> str:
    """
    Decrypts an encrypted field string back to plaintext.
    Returns original plaintext.
    """
    if not ciphertext:
        return ""
    try:
        decrypted_bytes = fernet.decrypt(ciphertext.encode('utf-8'))
        return decrypted_bytes.decode('utf-8')
    except Exception as e:
        logger.error(f"Failed to decrypt field: {e}")
        raise ValueError("Decryption failed. Invalid ciphertext or key mismatch.")

def reencrypt_field(ciphertext: str, old_key: str, new_key: str) -> str:
    """
    Key Rotation Utility:
    Re-encrypts a ciphertext from an old key to a new key during scheduled key rotations.
    """
    old_fernet = Fernet(old_key.encode('utf-8'))
    new_fernet = Fernet(new_key.encode('utf-8'))
    plaintext_bytes = old_fernet.decrypt(ciphertext.encode('utf-8'))
    return new_fernet.encrypt(plaintext_bytes).decode('utf-8')

"""
DOCUMENTED KEY ROTATION PLAN:
-----------------------------
1. Generate new Fernet key via `Fernet.generate_key()`.
2. Deploy new key into environment variable `NEW_FIELD_ENCRYPTION_KEY`.
3. Run background migration script to read all encrypted records from MongoDB,
   call `reencrypt_field(record.encrypted_field, old_key, new_key)`, and update records.
4. Replace `FIELD_ENCRYPTION_KEY` with the new key in production environment configuration.
5. Restart application services and verify zero decryption errors.
"""
