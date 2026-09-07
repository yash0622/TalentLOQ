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

def create_temp_token(user_id: str, device_id: Optional[str] = None) -> str:
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=settings.TEMP_TOKEN_EXPIRE_MINUTES)

    payload: Dict[str, Any] = {
        "sub": user_id,
        "role": "recruiter",
        "type": "temp_otp",
        "iat": int(now.timestamp()),
        "exp": expire,
    }
    if device_id:
        payload["device_id"] = device_id
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
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token"
        )
