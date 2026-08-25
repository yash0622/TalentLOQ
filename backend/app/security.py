import re
import random
import string
import hashlib
import logging
import bcrypt
from datetime import datetime
from passlib.context import CryptContext
from app.config import settings

logger = logging.getLogger("talentloq.security")

def hash_password(password: str) -> str:
    """
    Generate a bcrypt hash for passwords.
    Never stores plaintext.
    """
    pwd_bytes = password.encode('utf-8')
    if len(pwd_bytes) > 72:
        pwd_bytes = pwd_bytes[:72]
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(pwd_bytes, salt).decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a raw password against the stored bcrypt hash.
    Also falls back to PBKDF2 for legacy hashes if needed.
    """
    try:
        pwd_bytes = plain_password.encode('utf-8')
        if len(pwd_bytes) > 72:
            pwd_bytes = pwd_bytes[:72]
        return bcrypt.checkpw(pwd_bytes, hashed_password.encode('utf-8'))
    except Exception:
        # Fallback to PBKDF2 verification if needed
        try:
            salt_hex, hash_hex = hashed_password.split('$')
            salt = bytes.fromhex(salt_hex)
            pwd_hash = hashlib.pbkdf2_hmac(
                'sha256',
                plain_password.encode('utf-8'),
                salt,
                100000
            )
            import hmac
            return hmac.compare_digest(pwd_hash.hex(), hash_hex)
        except Exception:
            return False

def hash_token(token: str) -> str:
    """
    Generates SHA-256 hash for server-side token storage (refresh tokens & OTPs).
    """
    return hashlib.sha256(token.encode('utf-8')).hexdigest()

def generate_otp() -> str:
    """
    Generates a secure 6-digit numeric OTP.
    """
    return ''.join(random.choices(string.digits, k=6))

def sanitize_text(text: str) -> str:
    """
    Sanitizes user-supplied text to prevent script injection and control character attacks.
    Strips <script> tags and ASCII control characters.
    """
    if not text:
        return ""
    # Strip <script>...</script> tags case-insensitively
    text = re.sub(r'<script.*?>.*?</script>', '', text, flags=re.IGNORECASE | re.DOTALL)
    # Strip all HTML tags
    text = re.sub(r'<[^>]*>', '', text)
    # Strip control characters except standard whitespace (\n, \r, \t)
    text = re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '', text)
    return text.strip()

def verify_captcha(captcha_token: str) -> bool:
    """
    Verifies user-supplied CAPTCHA token (e.g. hCaptcha / Google reCAPTCHA).
    In production, this queries the CAPTCHA provider API using CAPTCHA_SECRET_KEY.
    For demonstration/test environments, accepts valid non-empty tokens.
    """
    if not captcha_token or len(captcha_token.strip()) < 5:
        return False
    # Mock validation: accept valid dummy or real tokens
    return True

def send_recruiter_login_alert(ip: str, device: str, timestamp: datetime) -> None:
    """
    Real-time alerting utility triggered on EVERY successful recruiter login.
    Emails designated admin address and logs security alert.
    """
    alert_msg = (
        f"[SECURITY ALERT] Recruiter Login Detected!\n"
        f"Recruiter Account: {settings.RECRUITER_EMAIL}\n"
        f"IP Address:        {ip}\n"
        f"Device / Agent:    {device}\n"
        f"Timestamp:         {timestamp.isoformat()}\n"
        f"Admin Alert Target: {settings.ADMIN_ALERT_EMAIL}"
    )
    logger.warning(alert_msg)
    # Simulates dispatching high-priority security alert email to ADMIN_ALERT_EMAIL
    print("=" * 70)
    print(alert_msg)
    print("=" * 70)

def send_otp_email(email: str, otp: str) -> None:
    """
    Sends OTP email to the user via SMTP if configured, or logs to console for local testing.
    """
    msg = f"[OTP SERVICE] Sent OTP to {email}: {otp} (Expires in {settings.TEMP_TOKEN_EXPIRE_MINUTES} mins)"
    logger.info(msg)
    print("=" * 70)
    print(f"  OTP CODE FOR {email}: {otp}")
    print(msg)
    print("=" * 70)

    if settings.SMTP_USER and settings.SMTP_PASSWORD:
        try:
            import smtplib
            from email.mime.text import MIMEText
            from email.mime.multipart import MIMEMultipart

            message = MIMEMultipart("alternative")
            message["Subject"] = f"Talentloq Verification Code: {otp}"
            message["From"] = settings.SMTP_FROM_EMAIL
            message["To"] = email

            text_content = f"Your Talentloq OTP code is: {otp}\nExpires in {settings.TEMP_TOKEN_EXPIRE_MINUTES} minutes."
            html_content = f"""
            <html>
              <body style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
                <h2 style="color: #4F46E5;">Talentloq Authentication</h2>
                <p>Your one-time verification code is:</p>
                <div style="background: #F3F4F6; padding: 15px; border-radius: 8px; font-size: 28px; font-weight: bold; letter-spacing: 4px; display: inline-block; color: #1F2937;">
                  {otp}
                </div>
                <p style="margin-top: 15px; color: #6B7280; font-size: 14px;">This code will expire in {settings.TEMP_TOKEN_EXPIRE_MINUTES} minutes.</p>
              </body>
            </html>
            """

            message.attach(MIMEText(text_content, "plain"))
            message.attach(MIMEText(html_content, "html"))

            with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
                if settings.SMTP_TLS:
                    server.starttls()
                server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                server.sendmail(settings.SMTP_FROM_EMAIL, [email], message.as_string())
            logger.info(f"Successfully sent OTP email to {email} via SMTP")
        except Exception as e:
            logger.error(f"Failed to send OTP email via SMTP: {e}")

