from datetime import datetime, timezone
from typing import Dict, Any, Callable, Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.jwt_utils import decode_token
from app.database import users_collection

security_bearer = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security_bearer)
) -> Dict[str, Any]:
    """
    Extracts Bearer access token, validates signature/expiration,
    and returns decoded token payload.
    """
    token = credentials.credentials
    payload = decode_token(token, expected_type="access")
    
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token claims"
        )
    return payload

async def get_optional_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(HTTPBearer(auto_error=False))
) -> Optional[Dict[str, Any]]:
    """
    Extracts Bearer access token if provided, returning None if unauthenticated.
    """
    if not credentials:
        return None
    try:
        return decode_token(credentials.credentials, expected_type="access")
    except Exception:
        return None

def require_role(required_role: str):
    """Authorization dependency builder for a single role."""
    if required_role == "recruiter":
        return require_roles(["recruiter", "admin"])
    return require_roles([required_role])

def require_roles(allowed_roles: list[str]):
    """
    Authorization dependency builder supporting multiple allowed roles.
    Rejects with 403 Forbidden if user's role is not in allowed_roles.
    """
    async def roles_checker(token_payload: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        token_role = token_payload.get("role")
        if token_role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Access forbidden. Allowed roles: {allowed_roles}, got '{token_role}'"
            )
        return token_payload
    return roles_checker

def require_recent_reauth(max_age_seconds: int = 300):
    """
    Authorization dependency builder for sensitive recruiter actions.
    Requires authentication within the last N seconds (e.g., 5 mins = 300s).
    """
    async def reauth_checker(token_payload: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        auth_time = token_payload.get("auth_time") or token_payload.get("iat")
        if not auth_time:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication timestamp missing. Please log in again."
            )
        
        now_ts = int(datetime.now(timezone.utc).timestamp())
        elapsed_seconds = now_ts - auth_time

        if elapsed_seconds > max_age_seconds:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Sensitive action requires recent re-authentication. Logged in {elapsed_seconds}s ago (max allowed: {max_age_seconds}s)."
            )
        return token_payload
    return reauth_checker
