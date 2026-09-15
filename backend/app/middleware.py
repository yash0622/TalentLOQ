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

def _describe_endpoint(method: str, path: str) -> str:
    """Returns human-readable description of what action/feature is being executed."""
    p = path.rstrip("/")
    if p == "/auth/me":
        return "Fetch Student Profile & Academic State"
    if p == "/auth/login":
        return "User Login & Verification"
    if p == "/auth/register":
        return "Student Account Registration"
    if p == "/auth/verify-otp":
        return "Two-Factor OTP Verification"
    if p == "/auth/refresh":
        return "Silent Token Refresh"
    if p == "/auth/logout":
        return "User Session Logout"
    if p == "/auth/resume":
        return "Resume Deletion / Clear" if method == "DELETE" else "Resume Access"
    if p == "/documents/upload":
        return "Document Upload -> RapidOCR & Mark/Skill Parsing"
    if p == "/documents/profile/verification-state":
        return "Check Document Verification State"
    if p == "/documents" and method == "GET":
        return "List User Uploaded Documents in GridFS"
    if p.startswith("/documents/") and method == "DELETE":
        return "Delete Document & Purge Extracted Data"
    if "/ai-match" in p:
        return "Student Drive AI Match & Prep Checklist"
    if "/ai-insight" in p:
        return "Recruiter 30s Candidate Screening Insight"
    if "/apply" in p:
        return "Submit Drive Application"
    if "my-applications" in p or p.endswith("/applications"):
        return "Fetch Student Application History"
    if p.startswith("/drives/student") or p == "/drives":
        return "Browse Placement Drives & Eligibility Gate"
    if p.startswith("/recruiter/candidates"):
        return "Review Candidates & AI Match Scores"
    if p.startswith("/recruiter/drives"):
        return "Manage Recruiter Placement Drives"
    if p.startswith("/chat"):
        return "Chat & In-App Messaging"
    if p.startswith("/interviews"):
        return "Interview Scheduling & Outcomes"
    if p.startswith("/announcements"):
        return "Campus Placement Announcements"
    if p in ["", "/health"]:
        return "Health Check"
    return "API Request"

class ApiMetricsLoggingMiddleware(BaseHTTPMiddleware):
    """
    Logs API method, path, response status code, latency, and feature description in terminal.
    """
    async def dispatch(self, request: Request, call_next):
        start_time = time.perf_counter()
        response = await call_next(request)
        duration_ms = (time.perf_counter() - start_time) * 1000

        status = response.status_code
        color = "\033[92m" if status < 400 else "\033[93m" if status < 500 else "\033[91m"
        cyan = "\033[96m"
        reset = "\033[0m"

        desc = _describe_endpoint(request.method, request.url.path)

        # Log to terminal with human-readable feature description
        print(
            f"[API CALL] {request.method:<6} {request.url.path:<38} -> {color}{status}{reset} ({duration_ms:>6.1f}ms) | {cyan}{desc}{reset}",
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