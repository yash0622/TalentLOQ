import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Load .env file
env_path = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

class Settings:
    RECRUITER_EMAIL: str = os.environ.get("RECRUITER_EMAIL", "talentloq.recruiter@gmail.com").lower()
    MONGODB_URL: str = os.environ.get("MONGODB_URL") or os.environ.get("MONGO_URI") or "mongodb://localhost:27017"
    DATABASE_NAME: str = os.environ.get("DATABASE_NAME", "talentloq_db")
    _raw_jwt = os.environ.get("JWT_SECRET") or os.environ.get("JWT_SECRET_KEY") or ""
    if not _raw_jwt:
        if "pytest" in sys.modules or any("pytest" in arg for arg in sys.argv):
            _raw_jwt = "test-secret-key-talentloq-secure-fallback-32chars"
        else:
            raise RuntimeError("CRITICAL SECURITY ERROR: JWT_SECRET environment variable is not set!")
    JWT_SECRET: str = _raw_jwt
    if not any("pytest" in m for m in sys.modules) and len(_raw_jwt) < 32:
        raise RuntimeError("CRITICAL: JWT_SECRET must be at least 32 characters for HS256 security.")
    JWT_ALGORITHM: str = os.environ.get("JWT_ALGORITHM", "HS256")
    # External LLM Keys
    GROQ_API_KEY: str = os.environ.get("GROQ_API_KEY", "")
    OPENROUTER_API_KEY: str = os.environ.get("OPENROUTER_API_KEY", "")
    GEMINI_API_KEY: str = os.environ.get("GEMINI_API_KEY", os.environ.get("GOOGLE_API_KEY", ""))
    MISTRAL_API_KEY: str = os.environ.get("MISTRAL_API_KEY", "")
    HUGGINGFACE_API_KEY: str = os.environ.get("HUGGINGFACE_API_KEY", "")

    ALLOWED_ORIGINS: str = os.environ.get("ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:8000,http://127.0.0.1:8000")
    
    # Token expiration configurations
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.environ.get("ACCESS_TOKEN_EXPIRE_MINUTES", "1440"))  # 24 hours
    REFRESH_TOKEN_EXPIRE_DAYS: int = int(os.environ.get("REFRESH_TOKEN_EXPIRE_DAYS", "30"))       # 30 days
    TEMP_TOKEN_EXPIRE_MINUTES: int = 15    # 15 min for recruiter OTP step
    DEVICE_VERIFY_EXPIRE_MINUTES: int = 15 # 15 min for device verification token
    
    # Recruiter security settings
    RECRUITER_INITIAL_PASSWORD: str = os.environ.get("RECRUITER_INITIAL_PASSWORD", "")
    ADMIN_ALERT_EMAIL: str = os.environ.get("ADMIN_ALERT_EMAIL", "admin@talentloq.com")
    CAPTCHA_ENABLED: bool = os.environ.get("CAPTCHA_ENABLED", "true").lower() == "true"
    CAPTCHA_SECRET_KEY: str = os.environ.get("CAPTCHA_SECRET_KEY", "")
    ENFORCE_RECRUITER_IP_RESTRICTION: bool = os.environ.get("ENFORCE_RECRUITER_IP_RESTRICTION", "false").lower() == "true"
    ALLOWED_RECRUITER_IPS: list[str] = [ip.strip() for ip in os.environ.get("ALLOWED_RECRUITER_IPS", "127.0.0.1,0.0.0.0/0").split(",") if ip.strip()]
    
    # Lockout thresholds
    RECRUITER_MAX_FAILED_ATTEMPTS: int = 3
    STUDENT_MAX_FAILED_ATTEMPTS: int = 5
    LOCKOUT_DURATION_MINUTES: int = 15

    # SMTP / Email settings
    SMTP_HOST: str = os.environ.get("SMTP_HOST", "smtp.gmail.com")
    SMTP_PORT: int = int(os.environ.get("SMTP_PORT", "587"))
    SMTP_USER: str = os.environ.get("SMTP_USER", "")
    SMTP_PASSWORD: str = os.environ.get("SMTP_PASSWORD", "")
    SMTP_TLS: bool = os.environ.get("SMTP_TLS", "true").lower() == "true"
    SMTP_FROM_EMAIL: str = os.environ.get("SMTP_FROM_EMAIL", "no-reply@talentloq.com")
    SHOW_DEV_OTP: bool = os.environ.get("SHOW_DEV_OTP", "false").lower() == "true"

settings = Settings()

RECRUITER_EMAILS = {
    settings.RECRUITER_EMAIL.lower(),
    "talentloq.recruiter@gmail.com",
    "telentloqrecruiter@gmail.com",
}

RESERVED_EMAILS = RECRUITER_EMAILS

def determine_role(email: str) -> str:
    """
    Determines system role based on exact email match.
    Returns 'recruiter' for authorized recruiter email addresses, otherwise 'student'.
    """
    email_clean = email.lower().strip()
    if email_clean in RECRUITER_EMAILS:
        return "recruiter"
    return "student"
