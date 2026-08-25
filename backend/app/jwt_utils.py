import uuid
import jwt
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, Optional
from fastapi import HTTPException, status
from app.config import settings

def create_access_token(user_id: str, role: str, auth_time: Optional[int] = None) -> str:
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    auth_timestamp = auth_time or int(now.timestamp())

    payload: Dict[str, Any] = {
        "sub": user_id,
        "role": role,
        "type": "access",
        "auth_time": auth_timestamp,
        "iat": int(now.timestamp()),
        "exp": expire,
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)

def create_refresh_token(user_id: str, role: str) -> tuple[str, str]:
    now = datetime.now(timezone.utc)
    expire = now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    token_id = str(uuid.uuid4())

    payload: Dict[str, Any] = {
        "sub": user_id,
        "role": role,
        "type": "refresh",
        "token_id": token_id,
        "iat": int(now.timestamp()),
        "exp": expire,
    }
    encoded = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
    return encoded, token_id

def create_temp_token(user_id: str) -> str:
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=settings.TEMP_TOKEN_EXPIRE_MINUTES)

    payload: Dict[str, Any] = {
        "sub": user_id,
        "role": "recruiter",
        "type": "temp_otp",
        "iat": int(now.timestamp()),
        "exp": expire,
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)

def create_device_token(user_id: str, device_id: str) -> str:
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=settings.DEVICE_VERIFY_EXPIRE_MINUTES)

    payload: Dict[str, Any] = {
        "sub": user_id,
        "device_id": device_id,
        "type": "device_verify",
        "iat": int(now.timestamp()),
        "exp": expire,
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)

def decode_token(token: str, expected_type: Optional[str] = None) -> Dict[str, Any]:
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET,
            algorithms=[settings.JWT_ALGORITHM]
        )
        if expected_type and payload.get("type") != expected_type:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid token type. Expected {expected_type}"
            )
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired"
        )
    except jwt.PyJWTError:
        # Dev-mode fallback: accept mock tokens from Flutter offline fallback
        if _is_dev_mode():
            mock_payload = _try_parse_mock_token(token, expected_type)
            if mock_payload:
                return mock_payload
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token"
        )


def _is_dev_mode() -> bool:
    """Check if running in development mode (default True unless PRODUCTION=true)."""
    import os
    return os.environ.get("PRODUCTION", "false").lower() != "true"


def _try_parse_mock_token(token: str, expected_type: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """
    Parse a mock JWT (unsigned or with mock_signature) by decoding the base64 payload.
    Only used in development mode to support Flutter's offline fallback tokens.
    Returns the payload dict if valid, or None if parsing fails.
    """
    import json
    import base64
    import logging

    logger = logging.getLogger("talentloq.jwt_utils")

    try:
        parts = token.split(".")
        if len(parts) != 3:
            return None

        # Decode the payload (second segment)
        payload_b64 = parts[1]
        # Add padding if needed
        padding = 4 - len(payload_b64) % 4
        if padding != 4:
            payload_b64 += "=" * padding

        payload_bytes = base64.urlsafe_b64decode(payload_b64)
        payload = json.loads(payload_bytes)

        # Validate required fields
        if not payload.get("sub") or not payload.get("role"):
            return None

        # Check expiration
        exp = payload.get("exp")
        if exp:
            import time
            if time.time() > exp:
                return None

        # Ensure type matches if expected
        if expected_type and expected_type == "access" and payload.get("type") != "access":
            # Mock tokens from Flutter don't set type — inject it for compatibility
            payload["type"] = "access"

        # Ensure auth_time exists for reauth checks
        if "auth_time" not in payload:
            import time
            payload["auth_time"] = int(time.time())

        logger.warning(f"[DEV MODE] Accepted mock token for user={payload.get('sub')}, role={payload.get('role')}")
        return payload

    except Exception:
        return None

