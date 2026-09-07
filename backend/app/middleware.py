import ipaddress
import logging
from fastapi import Request, HTTPException, status
from starlette.middleware.base import BaseHTTPMiddleware
from app.config import settings

logger = logging.getLogger("talentloq.security_middleware")

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """
    FastAPI Middleware injecting essential infrastructure security headers into every HTTP response.
    """
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self'; "
            "object-src 'none'; "
            "frame-ancestors 'none';"
        )
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains; preload"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        
        return response

import time

class ApiMetricsLoggingMiddleware(BaseHTTPMiddleware):
    """
    Logs API method, path, response status code, and latency in terminal with color highlights.
    """
    async def dispatch(self, request: Request, call_next):
        start_time = time.perf_counter()
        response = await call_next(request)
        duration_ms = (time.perf_counter() - start_time) * 1000

        status = response.status_code
        color = "\033[92m" if status < 400 else "\033[93m" if status < 500 else "\033[91m"
        reset = "\033[0m"

        # Log to terminal
        print(
            f"[API CALL] {request.method:<6} {request.url.path:<35} -> {color}{status}{reset} ({duration_ms:.1f}ms)",
            flush=True
        )
        return response

from typing import Union, List

def check_ip_in_cidrs(client_ip: str, allowed_cidrs: Union[str, List[str]]) -> bool:
    """
    Checks if client_ip belongs to any allowed CIDR ranges or specific IP strings.
    Supports either comma-separated string or list of CIDR/IP strings.
    """
    if not allowed_cidrs:
        return True
    
    try:
        ip_obj = ipaddress.ip_address(client_ip)
    except ValueError:
        return False

    raw_list = allowed_cidrs if isinstance(allowed_cidrs, list) else allowed_cidrs.split(",")
    for cidr_str in raw_list:
        cidr_str = str(cidr_str).strip()
        if not cidr_str:
            continue
        try:
            net = ipaddress.ip_network(cidr_str, strict=False)
            if ip_obj in net:
                return True
        except ValueError:
            if client_ip == cidr_str:
                return True
    return False

def verify_recruiter_ip_restriction(client_ip: str) -> None:
    """
    Optional network restriction for recruiter login specifically.
    Checks client IP against ALLOWED_RECRUITER_IPS if ENFORCE_RECRUITER_IP_RESTRICTION is enabled.
    Rejects with 403 Forbidden on violation.
    """
    if not settings.ENFORCE_RECRUITER_IP_RESTRICTION:
        return

    allowed_list = settings.ALLOWED_RECRUITER_IPS
    if not allowed_list:
        logger.warning("ENFORCE_RECRUITER_IP_RESTRICTION is true, but ALLOWED_RECRUITER_IPS is empty!")
        return

    if not check_ip_in_cidrs(client_ip, allowed_list):
        logger.warning(f"[SECURITY REJECT] Recruiter login attempted from unauthorized IP: {client_ip}")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Recruiter login restricted from this IP address"
        )