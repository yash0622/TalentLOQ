import sys
import asyncio
import logging
import traceback

# Windows Python 3.12 asyncio hot-reload safeguard
if sys.platform == "win32":
    try:
        import asyncio.selector_events
        _orig_close_self_pipe = asyncio.selector_events._BaseSelectorEventLoop._close_self_pipe

        def _safe_close_self_pipe(self):
            if getattr(self, "_ssock", None) is not None:
                try:
                    _orig_close_self_pipe(self)
                except Exception:
                    pass

        asyncio.selector_events._BaseSelectorEventLoop._close_self_pipe = _safe_close_self_pipe
        asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
    except Exception:
        pass

from fastapi import FastAPI, Request, Depends, HTTPException, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from app.routers import auth
from app.routers.auth import limiter
from app.config import settings
from app.middleware import SecurityHeadersMiddleware, ApiMetricsLoggingMiddleware
from app.dependencies import get_current_user, require_role, require_recent_reauth

from contextlib import asynccontextmanager
from app.database import init_db_indexes
from app.firebase_manager import init_firebase
from app.services.deadline_reminder_service import deadline_reminder_loop

logger = logging.getLogger("talentloq.main")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize Firebase once at startup
    init_firebase()
    # Non-blocking index initialization in background task for fast application startup
    index_task = asyncio.create_task(init_db_indexes())
    # Background periodic task for 24h/2h drive deadline reminders
    deadline_task = asyncio.create_task(deadline_reminder_loop())
    try:
        yield
    except (asyncio.CancelledError, KeyboardInterrupt):
        pass
    finally:
        if not index_task.done():
            index_task.cancel()
        if not deadline_task.done():
            deadline_task.cancel()
        try:
            from app.database import async_client
            async_client.close()
        except Exception:
            pass

app = FastAPI(
    title="Talentloq API",
    description="Campus Placement Tracker API with Role Identification, Authentication & Infrastructure Security",
    version="1.0.0",
    lifespan=lifespan,
)

# Attach API Metrics Logging Middleware
app.add_middleware(ApiMetricsLoggingMiddleware)

# Attach Security Headers Middleware
app.add_middleware(SecurityHeadersMiddleware)

# Attach GZip Response Compression Middleware (compresses responses >= 1KB)
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Slowapi state, middleware and exception handler
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS Configuration with Explicit Allowed Origins (ngrok URLs go in ALLOWED_ORIGINS env var)
origins_list = [origin.strip() for origin in settings.ALLOWED_ORIGINS.split(",") if origin.strip()]
dev_origin_regex = r"https?://(localhost|127\.0\.0\.1)(:[0-9]+)?"

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins_list if origins_list else ["http://localhost:3000"],
    allow_origin_regex=dev_origin_regex,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "X-Device-ID", "ngrok-skip-browser-warning"],
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

from app.routers import auth, admin_audit, recruiter, announcements, companies, drives_recruiter, drives_student, files, chat, interviews, documents, notifications

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
app.include_router(notifications.router)

@app.get("/", tags=["Health Check"])
@app.get("/health", tags=["Health Check"])
async def root():
    return {
        "status": "healthy",
        "app": "Talentloq API",
        "recruiter_configured": bool(settings.RECRUITER_EMAIL),
        "allowed_origins": origins_list,
    }