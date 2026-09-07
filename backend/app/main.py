import asyncio
import logging
import traceback
from fastapi import FastAPI, Request, Depends, HTTPException, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.routers import auth
from app.routers.auth import limiter
from app.config import settings
from app.middleware import SecurityHeadersMiddleware
from app.dependencies import get_current_user, require_role, require_recent_reauth

from contextlib import asynccontextmanager
from app.database import init_db_indexes

logger = logging.getLogger("talentloq.main")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize MongoDB indexes on startup
    try:
        await init_db_indexes()
        logger.info("MongoDB indexes initialized successfully.")
    except (asyncio.CancelledError, KeyboardInterrupt):
        pass
    except Exception as e:
        logger.warning(f"Could not initialize MongoDB indexes on startup: {e}")
    try:
        yield
    except (asyncio.CancelledError, KeyboardInterrupt):
        pass

app = FastAPI(
    title="Talentloq API",
    description="Campus Placement Tracker API with Role Identification, Authentication & Infrastructure Security",
    version="1.0.0",
    lifespan=lifespan,
)

# Attach Security Headers Middleware
app.add_middleware(SecurityHeadersMiddleware)

# Attach GZip Response Compression Middleware (compresses responses >= 1KB)
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Slowapi state and exception handler
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS Configuration with Explicit Allowed Origins & Controlled Dev Tunnel Regex
origins_list = [origin.strip() for origin in settings.ALLOWED_ORIGINS.split(",") if origin.strip()]
dev_origin_regex = r"https?://(localhost|127\.0\.0\.1)(:[0-9]+)?|https://.*\.ngrok-free\.dev"

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins_list if origins_list else ["http://localhost:3000"],
    allow_origin_regex=dev_origin_regex,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# Custom 422 Request Validation Error Handler (Log exact field validation failures)
from fastapi.exceptions import RequestValidationError

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = exc.errors()
    error_messages = []
    for err in errors:
        loc = " -> ".join([str(x) for x in err.get("loc", []) if x != "body"])
        msg = err.get("msg", "Invalid field value")
        error_messages.append(f"'{loc}': {msg}" if loc else msg)

    formatted_msg = "; ".join(error_messages)
    logger.warning(f"422 Validation Error on {request.url.path}: {formatted_msg}")

    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "detail": formatted_msg,
            "errors": errors
        }
    )

# Centralized Unhandled Exception Handler (Never leak stack traces to client)
@app.exception_handler(Exception)
async def centralized_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled Server Error on {request.url.path}: {exc}")
    logger.error(traceback.format_exc())

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "Internal server error. Please contact system administrator."}
    )

from app.routers import auth, admin_audit, recruiter, announcements, companies, drives_recruiter, drives_student, files, chat, interviews, documents

# Include Routers
app.include_router(files.router)
app.include_router(auth.router)
app.include_router(documents.router)
app.include_router(documents.profile_router)
app.include_router(admin_audit.router)
app.include_router(recruiter.router)
app.include_router(announcements.router)
app.include_router(companies.router)
app.include_router(drives_recruiter.router)
app.include_router(drives_student.router)
app.include_router(chat.router)
app.include_router(interviews.router)

@app.get("/", tags=["Health Check"])
@app.get("/health", tags=["Health Check"])
async def root():
    return {
        "status": "healthy",
        "app": "Talentloq API",
        "recruiter_configured": bool(settings.RECRUITER_EMAIL),
        "allowed_origins": origins_list,
    }

# ---------------------------------------------------------------------------
# Protected Endpoint Examples
# ---------------------------------------------------------------------------

@app.post("/recruiter/post-job", tags=["Recruiter Operations"])
async def post_job(
    token_payload: dict = Depends(require_role("recruiter")),
    reauth_payload: dict = Depends(require_recent_reauth(max_age_seconds=300)),
):
    return {
        "message": "Job posted successfully",
        "recruiter_id": token_payload["sub"],
        "auth_time": token_payload.get("auth_time"),
    }

@app.get("/student/profile", tags=["Student Operations"])
async def get_student_profile(
    token_payload: dict = Depends(require_role("student")),
):
    return {
        "message": "Student profile fetched",
        "student_id": token_payload["sub"],
    }
