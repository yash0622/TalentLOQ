# PROJECT_CONTEXT.md

## Project Overview
- **Project Name**: TalentLOQ (Campus Placement Tracker)
- **Purpose**: TalentLOQ is an end-to-end campus placement tracking platform designed for GSFC University students and corporate recruiters. It streamlines job applications, resume verification, interview scheduling, placement statistics, and security auditing with multi-role access control.
- **Main Features**:
  - **Student Portal**: Academic & profile management, resume PDF upload & native file viewing, placement job marketplace, application status tracking, broadcast announcements feed, and interview scheduling.
  - **Recruiter & Placement Officer Portal**: Job & internship drive management (Parser Agent auto-structuring), Candidate Review & Validation Dashboard (Matcher Agent skill gaps & student approval gate), Interview Scheduling & Outcome Logging (Selection Notifications), Cohort Analytics, Broadcast Announcements, Support Tickets, and Academic Record visibility.
  - **Security & Compliance**: Role-based access control (Student vs Recruiter), TLS Certificate Pinning, Device Fingerprinting (`X-Device-ID`), OTP verification, Rate Limiting (`slowapi`), AES-256 field encryption, audit logging, and recruiter single-account constraint.
- **Current Development Status**: Feature complete for Core Auth, Student Profile, Placement Marketplace, Resume Viewer, Recruiter & Placement Officer Portal suite, Security Middleware, and Admin Audit services. All dummy/ghost placeholder data removed; connected to live MongoDB backend.

---

## Tech Stack
- **Frontend**: Flutter (Dart 3.12+), Material 3 Design System, `google_fonts`, `dio` for HTTP networking, `flutter_secure_storage` for encrypted token storage, `local_auth` for biometric security, `file_picker` & `open_filex` for native resume management.
- **Backend**: Python 3.12+ with FastAPI (v0.109.2), Uvicorn ASGI server, Pydantic v2 data validation, `slowapi` rate limiting, `passlib`/`bcrypt` password hashing, PyJWT token engine.
- **Database**: MongoDB (via Motor async driver `motor.motor_asyncio` and PyMongo `pymongo` sync driver).
- **AI/ML Libraries**: Designed for AI decision logs and candidate matching index (`agent_runs` collection).
- **Authentication**: JWT Bearer Tokens (Short-lived 15-min Access Tokens, 7-day Refresh Tokens), OTP verification, Temp 2FA Tokens, Recruiter Device Binding Tokens.
- **Deployment & Networking**: Local Uvicorn server bridged via live ngrok HTTPS tunnel (`https://spotting-refuse-scorecard.ngrok-free.dev`), Android compileSdk 36.

---

## Architecture

### Overall Architecture
TalentLOQ uses a decoupled client-server architecture:
1. **Client Layer**: Flutter cross-platform mobile & web client managing state locally, executing certificate pinning, and storing secrets securely via `FlutterSecureStorage`.
2. **Gateway / API Layer**: FastAPI REST API enforcing security middleware (Security Headers, Rate Limiting, CORS, Device ID tracking, IP restrictions).
3. **Persistence Layer**: Async MongoDB Motor database with indexed collections (`users`, `students`, `audit_logs`, `refresh_tokens`, `otps`, `agent_runs`).

### Folder Structure
```
telentloq/
├── backend/
│   ├── app/
│   │   ├── main.py                   # FastAPI initialization & global middleware
│   │   ├── config.py                 # Pydantic environment configuration
│   │   ├── database.py               # Motor async & PyMongo connection & indexes
│   │   ├── dependencies.py           # Dependency injection (Auth, Roles, Re-auth)
│   │   ├── encryption.py             # AES-256 GCM field encryption utilities
│   │   ├── jwt_utils.py              # JWT encoding/decoding & token creation
│   │   ├── middleware.py             # Security headers & IP restrictions
│   │   ├── models.py                 # Pydantic schemas & MongoDB models
│   │   ├── security.py               # Password hashing, OTP, CAPTCHA, email alerts
│   │   ├── upload_validator.py       # File extension & MIME type validation
│   │   └── routers/
│   │       ├── auth.py               # Auth endpoints (Register, Login, OTP, Refresh, Profile)
│   │       └── admin_audit.py        # Admin audit logs & AI agent decision endpoints
│   ├── scripts/                      # DB cleanup & seeding scripts
│   └── tests/                        # Pytest suite for auth & security
├── lib/
│   ├── main.dart                     # Flutter entry point & global route initialization
│   ├── mock_data/                    # Type-safe dynamic data sources
│   ├── models/                       # Dart data models (Job, Candidate, Application, etc.)
│   ├── navigation/                   # Bottom navigation & role-based routing
│   ├── network/                      # Dio ApiClient & CertPinningConfig
│   ├── screens/                      # UI screens grouped by feature domain
│   │   ├── application/              # Application tracking screens
│   │   ├── auth/                     # Login & Registration screens
│   │   ├── chat/                     # Recruiter-Student messaging screens
│   │   ├── dashboard/                # Student & Recruiter dashboard screens
│   │   ├── interview/                # Interview schedule screens
│   │   ├── jobs/                     # Job marketplace & detail screens
│   │   ├── profile/                  # Student profile & Resume viewer screens
│   │   └── recruiter/                # Candidate search & detail screens
│   ├── services/                     # TokenStorageService, AuthService, SecurityService
│   ├── theme/                        # AppColors & Material 3 theme configuration
│   └── widgets/                      # Reusable UI widgets
├── pubspec.yaml                      # Flutter dependencies & metadata
└── README.md                         # General repository information
```

### Major Modules
- **Authentication Service (`backend/app/routers/auth.py` & `lib/services/auth_service.dart`)**: Handles student registration, login, OTP verification, device binding, and token refresh.
- **Security & Audit Module (`backend/app/middleware.py` & `backend/app/audit_service.py`)**: Enforces recruiter IP restrictions, HTTP security headers, and structured audit logs.
- **Student Profile & Resume Viewer (`lib/screens/profile/profile_applications_screen.dart`)**: Handles PDF resume uploads, local storage persistence, non-truncated clean 2-row UI layout, and direct native document opening using `open_filex`.
- **Dashboard & Job Marketplace (`lib/screens/dashboard/` & `lib/screens/jobs/`)**: Renders campus job opportunities, application metrics, interview alerts, and responsive empty state cards.

### Data Flow
1. User actions trigger UI state updates in Flutter screens.
2. Network calls pass through `ApiClient` (`dio`), attaching `X-Device-ID` and `Authorization: Bearer <token>`.
3. Requests cross TLS Certificate Pinning validation before hitting backend ngrok tunnel.
4. FastAPI endpoints validate inputs via Pydantic models and sanitize strings.
5. Auth dependencies inspect JWT signatures, roles, and re-authentication limits.
6. DB operations run asynchronously on MongoDB via Motor.
7. Audit log entries are generated for security-critical actions.

---

## Important Components

### 1. `ApiClient` (`lib/network/api_client.dart`)
- **Purpose**: Centralized HTTP client singleton configured with Dio.
- **Responsibilities**: Manages base URL resolution, custom TLS certificate validation (`CertPinningConfig`), `X-Device-ID` header injection, Bearer token injection, and automatic silent refresh on 401 Unauthorized errors.
- **Dependencies**: `dio`, `flutter_secure_storage`, `TokenStorageService`, `CertPinningConfig`.
- **Related Files**: `lib/network/cert_pinning_config.dart`, `lib/services/token_storage_service.dart`.

### 2. `AuthRouter` (`backend/app/routers/auth.py`)
- **Purpose**: Backend auth and user profile router.
- **Responsibilities**: Registration for `@gsfcuniversity.ac.in` students, recruiter authentication with IP filtering, 2FA OTP verification, JWT token issuance, and avatar/resume upload handling.
- **Dependencies**: `FastAPI`, `slowapi`, `UserModel`, `StudentModel`, `jwt_utils`, `security`.
- **Related Files**: `backend/app/models.py`, `backend/app/security.py`, `backend/app/dependencies.py`.

### 3. `ProfileApplicationsScreen` (`lib/screens/profile/profile_applications_screen.dart`)
- **Purpose**: Displays student profile, academic metrics, and resume document management.
- **Responsibilities**: Minimalist formal design, dynamic CGPA/backlog display, PDF file picker, non-truncated full-width resume header, and icon-only actions (Show Document, Download, Replace, Delete).
- **Dependencies**: `file_picker`, `open_filex`, `TokenStorageService`, `AppColors`.
- **Related Files**: `lib/services/token_storage_service.dart`, `lib/theme/app_colors.dart`.

---

## Database

### Collections & Schema Summary

1. **`users` Collection**:
   - `user_id` (str, unique UUID index)
   - `email` (str, unique index, lowercased)
   - `full_name` (str)
   - `password_hash` (str, bcrypt hash)
   - `role` (str, `"student"` | `"recruiter"`)
   - `created_at` (datetime)
   - `is_verified` (bool)
   - `trusted_devices` (list of str, recruiter device tokens)
   - `must_change_password` (bool)
   - `failed_login_attempts` (int)
   - `lockout_until` (datetime, optional)

2. **`students` Collection**:
   - `student_id` (str, unique UUID index)
   - `user_id` (str, unique index, foreign key to `users.user_id`)
   - `full_name` (str)
   - `education` (str)
   - `CGPA` (float, 0.0 - 10.0)
   - `active_backlogs` (int)
   - `closed_backlogs` (int)
   - `skills` (list of str)

3. **`audit_logs` Collection**:
   - `log_id` (str, UUID index)
   - `user_id` (str, indexed)
   - `action` (str)
   - `ip` (str)
   - `device` (str)
   - `timestamp` (datetime, indexed)

4. **`refresh_tokens` Collection**:
   - `token_id` (str, unique index)
   - `user_id` (str)
   - `token_hash` (str)
   - `expires_at` (datetime, MongoDB TTL index for automatic expiration)
   - `revoked` (bool)

5. **`otps` Collection**:
   - `otp_id` (str, UUID index)
   - `user_id` (str, indexed)
   - `otp_hash` (str)
   - `expires_at` (datetime, MongoDB TTL index)
   - `attempts` (int)

6. **`agent_runs` Collection**:
   - AI Decision logs and screening execution output.

---

## APIs

### Authentication & User Endpoints (`/auth`)
- `POST /auth/register`: Public student registration (restricted to `@gsfcuniversity.ac.in`). Rate limit: 5/15min.
- `POST /auth/login`: Account authentication. Checks account lockout, recruiter IP restrictions, and device verification requirements.
- `POST /auth/verify-otp`: Validates 6-digit OTP code for 2FA login.
- `POST /auth/verify-device`: Verifies new recruiter device token.
- `POST /auth/refresh`: Issues new access token using a valid refresh token.
- `POST /auth/logout`: Revokes refresh token and logs out user session.
- `GET /auth/me`: Retrieves current authenticated user profile.
- `GET /auth/student-profile`: Fetches student profile data for authenticated student.
- `PUT /auth/student-profile`: Updates CGPA, backlogs, skills, or education info.

### Admin & Security Monitoring Endpoints (`/admin`)
- `GET /admin/audit-logs`: Admin audit log viewer (requires `"recruiter"` role and recent re-auth within 300 seconds).
- `GET /admin/agent-runs`: AI decision run logs for recruiter screening review.

---

## Business Logic

### Core Workflows
1. **Student Registration & Authentication**:
   - Student submits registration with `@gsfcuniversity.ac.in` domain.
   - User account and Student record created in database.
   - On login, password verified with `bcrypt`. On success, Access (15m) & Refresh (7d) JWT tokens are issued.
2. **Recruiter Security Protocol**:
   - Recruiter login checks exact allowed IP list.
   - Recruiter accounts require device verification token (`X-Device-ID`) or OTP 2FA.
3. **Resume Document Flow**:
   - Student selects local PDF resume using `file_picker`.
   - File path and metadata stored securely in device storage (`TokenStorageService`).
   - Tapping Show Document launches native PDF viewer via `open_filex`.

### Security Logic
- **Password Policies**: Minimum 8 characters, hashed with `bcrypt`.
- **Account Lockout**: 5 failed login attempts lock account for 15 minutes.
- **Rate Limiting**: `slowapi` rate limits authentication endpoints (5/15min).
- **Session Protection**: Access tokens expire in 15 minutes; silent refresh automatically negotiates new access tokens without user interruption.

---

## Configuration

### Environment Variables (`backend/.env`)
- `MONGODB_URL`: MongoDB connection string (e.g., `mongodb://localhost:27017`).
- `DATABASE_NAME`: Database name (`talentloq_db`).
- `JWT_SECRET_KEY`: Secret key for JWT signature validation.
- `RECRUITER_EMAIL`: Primary reserved recruiter email.
- `RECRUITER_IP_ALLOWLIST`: Comma-separated allowed IPs for recruiter logins.
- `ALLOWED_ORIGINS`: Origins allowed for CORS.
- `ENCRYPTION_KEY`: Secret key for AES-256 field encryption.

### Build Configuration
- **Android `compileSdk`**: Updated to `36` in `android/app/build.gradle.kts`.
- **Flutter SDK**: `^3.12.2`.

---

## Current Progress
- [x] **Backend Infrastructure**: FastAPI app with security middleware, MongoDB integration, and JWT auth system.
- [x] **Student Profile**: Academic summary, backlog tracking, technical skills display, and formal UI styling.
- [x] **Resume Document Integration**: PDF picker, `open_filex` native document viewer, 2-row layout with full file name display, and icon-only action bar.
- [x] **Empty State Handling**: Responsive empty state cards when no companies or placement drives are registered.
- [x] **Automated Test Coverage**: 28 passing pytest test cases for backend security & auth flow; clean `flutter analyze`.

---

## Change Log
- **2026-08-06**: Integrated `open_filex` for native PDF viewing, updated Resume card to a 2-row full-width layout with icon-only action buttons (`Eye`, `Download`, `Edit Document`, `Trash`), cleared hardcoded Alex ghost data, and added clean empty state views.
