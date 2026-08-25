# Talentloq Secrets Rotation Runbook

**Version**: 1.0  
**Classification**: Internal / Confidential Security Document  
**Target System**: Talentloq Campus Placement Tracker (Backend API & Auth System)

---

## Executive Overview
This runbook details zero-downtime operational procedures for rotating critical security credentials in the Talentloq production environment:
1. **JWT Secret Key** (`JWT_SECRET`)
2. **Field-Level AES Encryption Key** (`FIELD_ENCRYPTION_KEY`)
3. **Recruiter Account Credentials** (`telentloqrecruiter@gmail.com`)
4. **External AI API Keys** (`OPENROUTER_API_KEY`, `GROQ_API_KEY`)

---

## 1. JWT Secret Key Rotation Runbook

### Purpose
Rotates the signing secret (`JWT_SECRET`) used for signing Access, Refresh, and OTP tokens to mitigate token leaks or routine quarterly key rotation policies.

### Invalidation Impact
- Active refresh tokens signed under the old secret are invalidated upon secret replacement. Users will be prompted to log in again upon refresh token expiry.

### Rotation Procedure

#### Step 1: Generate New Cryptographic Key
Generate a 256-bit URL-safe random key:
```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

#### Step 2: Deploy Secondary Key Acceptance (Dual-Secret Phase)
1. Update deployment configuration with `JWT_SECRET_PRIMARY=<new_key>` and `JWT_SECRET_FALLBACK=<old_key>`.
2. The API attempts decoding with `JWT_SECRET_PRIMARY` first; if signature fails, it falls back to `JWT_SECRET_FALLBACK`.
3. New tokens are signed exclusively using `JWT_SECRET_PRIMARY`.

#### Step 3: Revoke Stored Refresh Tokens (Forced Invalidation)
Execute token revocation script to invalidate all active refresh tokens in MongoDB:
```bash
python -c "from pymongo import MongoClient; client = MongoClient('mongodb://localhost:27017'); client['talentloq_db']['refresh_tokens'].update_many({}, {'\$set': {'revoked': True}})"
```

#### Step 4: Remove Fallback Secret
After 30 minutes (matching `ACCESS_TOKEN_EXPIRE_MINUTES`), remove `JWT_SECRET_FALLBACK` and promote `JWT_SECRET_PRIMARY` to `JWT_SECRET`.

---

## 2. Field-Level AES Encryption Key Rotation Runbook

### Purpose
Rotates the Fernet AES-128-CBC key (`FIELD_ENCRYPTION_KEY`) used for encrypting PII and resume documents in MongoDB.

### Zero-Downtime Migration Procedure

#### Step 1: Generate New Fernet Encryption Key
```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

#### Step 2: Set Environment Variables
```ini
FIELD_ENCRYPTION_KEY_OLD=<current_production_key>
FIELD_ENCRYPTION_KEY_NEW=<newly_generated_key>
```

#### Step 3: Run Database Migration Script
Run the built-in re-encryption script:
```python
import os
from pymongo import MongoClient
from cryptography.fernet import Fernet

old_key = os.environ["FIELD_ENCRYPTION_KEY_OLD"]
new_key = os.environ["FIELD_ENCRYPTION_KEY_NEW"]

old_f = Fernet(old_key.encode())
new_f = Fernet(new_key.encode())

client = MongoClient(os.environ.get("MONGODB_URL", "mongodb://localhost:27017"))
db = client[os.environ.get("DATABASE_NAME", "talentloq_db")]

# Migrate Students collection encrypted PII
for student in db["students"].find():
    if "encrypted_pii" in student:
        try:
            plaintext = old_f.decrypt(student["encrypted_pii"].encode()).decode()
            new_ciphertext = new_f.encrypt(plaintext.encode()).decode()
            db["students"].update_one({"_id": student["_id"]}, {"$set": {"encrypted_pii": new_ciphertext}})
        except Exception as e:
            print(f"Error migrating student {student['student_id']}: {e}")

print("[SUCCESS] Field-level AES encryption key migration complete.")
```

#### Step 4: Update Production Configuration
Promote `FIELD_ENCRYPTION_KEY_NEW` to `FIELD_ENCRYPTION_KEY` in production `.env` and restart application services.

---

## 3. Recruiter Master Password Rotation Runbook

### Purpose
Rotates the recruiter account password (`telentloqrecruiter@gmail.com`) and forces a password change on next login.

### Procedure

#### Step 1: Update Environment Config
Update `.env` on production server:
```ini
RECRUITER_INITIAL_PASSWORD=<new_strong_password>
```

#### Step 2: Execute Recruiter Password Reset Script
```python
import os
from pymongo import MongoClient
import bcrypt

new_password = os.environ["RECRUITER_INITIAL_PASSWORD"]
pwd_bytes = new_password.encode('utf-8')[:72]
hashed = bcrypt.hashpw(pwd_bytes, bcrypt.gensalt()).decode('utf-8')

client = MongoClient(os.environ.get("MONGODB_URL", "mongodb://localhost:27017"))
db = client[os.environ.get("DATABASE_NAME", "talentloq_db")]

recruiter_email = os.environ.get("RECRUITER_EMAIL", "telentloqrecruiter@gmail.com").lower()

db["users"].update_one(
    {"email": recruiter_email},
    {"$set": {
        "password_hash": hashed,
        "must_change_password": True,
        "failed_login_attempts": 0,
        "lockout_until": None
    }}
)

# Revoke all active recruiter refresh tokens
recruiter_user = db["users"].find_one({"email": recruiter_email})
if recruiter_user:
    db["refresh_tokens"].update_many(
        {"user_id": recruiter_user["user_id"]},
        {"$set": {"revoked": True}}
    )

print(f"[SUCCESS] Recruiter password rotated. Active sessions revoked for {recruiter_email}.")
```

---

## 4. AI API Keys Rotation (OpenRouter / Groq)

### Procedure
1. Log into OpenRouter Dashboard / Groq Console and issue a new API key.
2. Update `.env`:
   ```ini
   OPENROUTER_API_KEY=sk-or-v1-new-key-value
   GROQ_API_KEY=gsk_new-groq-key-value
   ```
3. Perform zero-downtime rolling restart of FastAPI instances (`uvicorn` reload).
4. Revoke old API keys in OpenRouter / Groq developer consoles.

---

## 5. Security Audit Log Verification
Following any secrets rotation, verify rotation events in the audit log via:
```bash
curl -X GET "http://localhost:8000/admin/audit-logs?limit=10" \
  -H "Authorization: Bearer <recruiter_access_token>"
```
