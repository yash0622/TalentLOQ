import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env file
env_path = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

class Settings:
    RECRUITER_EMAIL: str = os.environ.get("RECRUITER_EMAIL", "talentloq.recruiter@gmail.com").lower()
    MONGODB_URL: str = os.environ.get("MONGODB_URL", "mongodb://localhost:27017")
    DATABASE_NAME: str = os.environ.get("DATABASE_NAME", "talentloq_db")
    JWT_SECRET: str = os.environ.get("JWT_SECRET", "super-secret-jwt-key-minimum-256-bits")
    JWT_ALGORITHM: str = "HS256"
    ALLOWED_ORIGINS: str = os.environ.get("ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:8000,http://127.0.0.1:8000")
    
    # Token expiration configurations
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15  # 15-30 min
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7     # 7 days
    TEMP_TOKEN_EXPIRE_MINUTES: int = 5     # 5 min for recruiter OTP step
    DEVICE_VERIFY_EXPIRE_MINUTES: int = 15 # 15 min for device verification token
    
    # Recruiter security settings
    RECRUITER_INITIAL_PASSWORD: str = os.environ.get("RECRUITER_INITIAL_PASSWORD", "ChangeMeRecruiter2026!")
    ADMIN_ALERT_EMAIL: str = os.environ.get("ADMIN_ALERT_EMAIL", "admin@talentloq.com")
    CAPTCHA_SECRET_KEY: str = os.environ.get("CAPTCHA_SECRET_KEY", "mock-captcha-secret-key")
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
    SHOW_DEV_OTP: bool = os.environ.get("SHOW_DEV_OTP", "true").lower() == "true"

settings = Settings()

RECRUITER_EMAILS = {
    settings.RECRUITER_EMAIL.lower(),
    "talentloq.recruiter@gmail.com",
}

RESERVED_EMAILS = RECRUITER_EMAILS

def determine_role(email: str) -> str:
    """
    Determines system role based on email address.
    Returns "recruiter" for recruiter email variants, otherwise "student".
    """
    email_clean = email.lower().strip()
    if email_clean in RECRUITER_EMAILS or "recruiter" in email_clean:
        return "recruiter"
    return "student"
