from datetime import datetime, timezone
from typing import List, Literal, Optional, Generic, TypeVar, Dict, Any
from pydantic import BaseModel, EmailStr, Field, field_validator
import uuid
import re

T = TypeVar("T")

# Role Types
RoleType = Literal["student", "recruiter"]

# ---------------------------------------------------------------------------
# 1. MongoDB Document Models
# ---------------------------------------------------------------------------

class UserModel(BaseModel):
    """
    MongoDB schema for 'users' collection.
    """
    user_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    email: EmailStr
    full_name: str = Field(default="Student User")
    password_hash: str
    role: RoleType
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    is_verified: bool = False
    trusted_devices: List[str] = Field(default_factory=list)  # Recruiter only
    must_change_password: bool = False
    failed_login_attempts: int = 0
    lockout_until: Optional[datetime] = None

class StudentModel(BaseModel):
    """
    MongoDB schema for 'students' collection.
    Canonical profile record for student candidates.
    """
    student_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str  # Foreign key referencing UserModel.user_id
    full_name: str = Field(default="Student User")
    email: Optional[str] = None
    university: str = Field(default="GSFC University")
    education: str = Field(default="")
    CGPA: float = Field(default=0.0, ge=0.0, le=10.0)
    active_backlogs: int = Field(default=0, ge=0)
    closed_backlogs: int = Field(default=0, ge=0)
    skills: List[str] = Field(default_factory=list)
    languages: List[str] = Field(default_factory=list)
    coding_languages: List[str] = Field(default_factory=list)
    spoken_languages: List[str] = Field(default_factory=list)
    social_links: Dict[str, str] = Field(default_factory=dict)
    linkedin_url: Optional[str] = None
    github_url: Optional[str] = None
    leetcode_url: Optional[str] = None
    hackerrank_url: Optional[str] = None
    codeforces_url: Optional[str] = None
    kaggle_url: Optional[str] = None
    geeksforgeeks_url: Optional[str] = None
    twitter_url: Optional[str] = None
    has_resume: bool = False
    resume_url: Optional[str] = None
    resume_filename: Optional[str] = None

    # Academic verified fields (Source-of-truth from Marksheets)
    tenth_percentage: Optional[float] = Field(default=None, ge=0.0, le=100.0)
    tenth_board: Optional[str] = None
    tenth_passing_year: Optional[int] = None
    twelfth_percentage: Optional[float] = Field(default=None, ge=0.0, le=100.0)
    twelfth_board: Optional[str] = None
    twelfth_passing_year: Optional[int] = None
    diploma_cgpa: Optional[float] = Field(default=None, ge=0.0, le=10.0)
    diploma_college: Optional[str] = None
    current_semester: Optional[int] = Field(default=None, ge=1, le=12)
    branch: Optional[str] = None
    enrollment_number: Optional[str] = None
    sgpa: Optional[float] = Field(default=None, ge=0.0, le=10.0)

    # Verification Metadata & Provenance tracking
    verified_fields: Dict[str, Any] = Field(default_factory=dict)
    documents: Dict[str, Any] = Field(default_factory=dict)

class VerificationDocumentModel(BaseModel):
    """
    MongoDB schema for 'verification_documents' collection.
    Stores metadata, hashes, extracted values, and verification states of uploaded academic files.
    """
    document_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    student_id: str
    user_id: str
    document_type: str  # RESUME, TENTH_MARKSHEET, TWELFTH_MARKSHEET, DIPLOMA_MARKSHEET, UG_MARKSHEET, UNKNOWN
    filename: str
    file_hash: str  # SHA-256 for change detection & deduplication
    grid_file_id: str
    file_url: str
    processing_status: str = Field(default="PROCESSING")  # PROCESSING, VERIFIED, REVIEW_REQUIRED, MANUAL_REVIEW, FAILED, REPLACED
    extracted_data: Dict[str, Any] = Field(default_factory=dict)
    ocr_confidence: float = Field(default=0.0, ge=0.0, le=100.0)
    extraction_confidence: float = Field(default=0.0, ge=0.0, le=100.0)
    validation_confidence: float = Field(default=0.0, ge=0.0, le=100.0)
    validation_errors: List[str] = Field(default_factory=list)
    uploaded_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    verified_at: Optional[datetime] = None
    processed_at: Optional[datetime] = None

class VerificationAuditModel(BaseModel):
    """
    MongoDB schema for 'verification_audits' collection.
    Immutable log of every field modification initiated by the verification pipeline.
    """
    audit_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    student_id: str
    field_name: str
    old_value: Any = None
    new_value: Any = None
    source_document_id: str
    source_document_type: str
    reason: str = "Document Verification Sync"
    status: str = "VERIFIED"
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

class AuditLogModel(BaseModel):
    """
    MongoDB schema for 'audit_logs' collection.
    """
    log_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    action: str
    ip: str
    device: str
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

class RefreshTokenModel(BaseModel):
    """
    MongoDB schema for 'refresh_tokens' collection.
    """
    token_id: str
    user_id: str
    token_hash: str
    expires_at: datetime
    revoked: bool = False

class OTPModel(BaseModel):
    """
    MongoDB schema for 'otps' collection.
    """
    otp_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    otp_hash: str
    expires_at: datetime
    attempts: int = 0

class JobPostModel(BaseModel):
    """
    MongoDB schema for 'job_postings' collection.
    """
    job_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    title: str
    company: str
    location: str = Field(default="San Francisco, CA (Remote)")
    job_type: str = Field(default="Full-Time")
    salary_range: str = Field(default="₹12L - ₹18L / yr")
    description: str
    requirements: List[str] = Field(default_factory=list)
    min_cgpa: float = Field(default=6.0, ge=0.0, le=10.0)
    required_skills: List[str] = Field(default_factory=list)
    deadline: str
    status: Literal["active", "closed"] = "active"
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    # Parser Agent extracted fields
    extracted_skills: List[str] = Field(default_factory=list)
    cgpa_cutoff: float = Field(default=6.0)
    deadline_extracted: str = Field(default="")
    parsing_confidence: float = Field(default=0.95)

class CompanyListingModel(BaseModel):
    """
    MongoDB schema for 'company_listings' collection.
    """
    listing_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    company_name: str
    company_email: str
    description: str
    pdf_url: Optional[str] = None
    interview_job: str
    bond_time: str = Field(default="0 years")
    interview_datetime: str
    interview_venue: str
    cgpa_criteria: float = Field(default=6.0, ge=0.0, le=10.0)
    status: Literal["draft", "published", "closed"] = "draft"
    posted_by: str  # Recruiter user_id
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

class CandidateApplicationModel(BaseModel):
    """
    MongoDB schema for 'applications' collection.
    """
    app_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    job_id: Optional[str] = None
    listing_id: Optional[str] = None
    drive_id: Optional[str] = None
    student_id: str
    resume_id_used: Optional[str] = None
    status: str = Field(default="applied")
    meets_cgpa_criteria: bool = False
    applied_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    match_score: float = Field(default=0.85, ge=0.0, le=1.0)
    skill_gaps: List[str] = Field(default_factory=list)
    is_auto_applied: bool = False
    student_approved: bool = True
    validation_status: Literal["pending", "valid", "not_valid"] = "pending"
    current_step: int = 1
    total_steps: int = 4
    email_client_opened_at: Optional[datetime] = None

class InterviewModel(BaseModel):
    """
    MongoDB schema for 'interviews' collection.
    """
    interview_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    app_id: str
    student_id: str
    job_id: str
    scheduled_time: str
    interview_type: str = Field(default="Technical Deep Dive")
    meeting_link: str = Field(default="https://talentloq.meet/interview-hd")
    status: Literal["scheduled", "passed", "failed", "next_round"] = "scheduled"
    feedback: str = Field(default="")
    notified_student: bool = True
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

class AnnouncementModel(BaseModel):
    """
    MongoDB schema for 'announcements' collection.
    """
    announcement_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    title: str
    content: str
    author_email: str = Field(default="talentloq.recruiter@gmail.com")
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

class SupportTicketModel(BaseModel):
    """
    MongoDB schema for 'support_tickets' collection.
    """
    ticket_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    student_id: str
    student_name: str
    subject: str
    issue_description: str
    ai_draft_flagged: bool = False
    status: Literal["open", "resolved"] = "open"
    recruiter_response: Optional[str] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


# ---------------------------------------------------------------------------
# 2. API Request & Response DTOs
# ---------------------------------------------------------------------------

def sanitize_string(v: str) -> str:
    if isinstance(v, str):
        v = re.sub(r'<script.*?>.*?</script>', '', v, flags=re.IGNORECASE | re.DOTALL)
        v = re.sub(r'<[^>]*>', '', v)
        v = re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '', v)
        return v.strip()
    return v

class StudentRegisterRequest(BaseModel):
    full_name: str = Field(default="Student User", alias="full_name")
    email: EmailStr
    password: str = Field(..., min_length=8, description="Password must be at least 8 characters")
    education: str = Field(default="B.Tech Computer Science")
    CGPA: float = Field(default=8.0, ge=0.0, le=10.0, alias="cgpa")
    active_backlogs: int = Field(default=0, ge=0)
    closed_backlogs: int = Field(default=0, ge=0)
    skills: List[str] = Field(default_factory=list)

    model_config = {
        "populate_by_name": True
    }

    @field_validator('full_name', mode='after')
    def sanitize_name(cls, v: str) -> str:
        return sanitize_string(v)

    @field_validator('education', mode='after')
    def sanitize_education(cls, v: str) -> str:
        return sanitize_string(v)

    @field_validator('skills', mode='after')
    def sanitize_skills(cls, v: List[str]) -> List[str]:
        return [sanitize_string(s) for s in v]

class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    captcha_token: Optional[str] = None

class VerifyOTPRequest(BaseModel):
    temp_token: str
    otp: str = Field(min_length=6, max_length=6)

class VerifyDeviceRequest(BaseModel):
    token: str

class RefreshTokenRequest(BaseModel):
    refresh_token: str

class LogoutRequest(BaseModel):
    refresh_token: str

class PasswordChangeRequest(BaseModel):
    old_password: str
    new_password: str = Field(min_length=8)

class UserResponse(BaseModel):
    user_id: str
    email: str
    full_name: str = Field(default="Student User")
    role: RoleType
    created_at: datetime
    is_verified: bool
    must_change_password: bool

class RegisterResponse(BaseModel):
    message: str
    user: UserResponse
    student_id: str

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    must_change_password: bool = False

# Recruiter DTOs
class JobCreateRequest(BaseModel):
    title: str
    company: str
    location: str = "San Francisco, CA (Remote)"
    job_type: str = "Full-Time"
    salary_range: str = "₹12L - ₹18L / yr"
    description: str
    requirements: List[str] = Field(default_factory=list)
    min_cgpa: float = Field(default=6.0, ge=0.0, le=10.0)
    required_skills: List[str] = Field(default_factory=list)
    deadline: str

class JobUpdateRequest(BaseModel):
    title: Optional[str] = None
    company: Optional[str] = None
    description: Optional[str] = None
    min_cgpa: Optional[float] = None
    required_skills: Optional[List[str]] = None
    deadline: Optional[str] = None
    status: Optional[Literal["active", "closed"]] = None

class ApplicationValidateRequest(BaseModel):
    validation_status: Literal["valid", "not_valid"]

class InterviewScheduleRequest(BaseModel):
    app_id: str
    student_id: str
    job_id: str
    scheduled_time: str
    interview_type: str = "Technical Deep Dive"
    meeting_link: str = "https://talentloq.meet/interview-hd"

class InterviewOutcomeRequest(BaseModel):
    status: Optional[str] = "passed"
    outcome: Optional[str] = None
    feedback: Optional[str] = ""
    notes: Optional[str] = ""

class AnnouncementCreateRequest(BaseModel):
    title: str
    content: Optional[str] = None
    message: Optional[str] = None
    target_audience: Optional[str] = "ALL"

class SupportTicketRespondRequest(BaseModel):
    response: str

# Company Listing & Extended Application Pydantic DTOs
class CompanyListingCreate(BaseModel):
    company_name: str
    company_email: EmailStr
    description: str
    pdf_url: Optional[str] = None
    interview_job: str
    bond_time: str = "0 years"
    interview_datetime: str
    interview_venue: str
    cgpa_criteria: float = Field(default=6.0, ge=0.0, le=10.0)
    status: Literal["draft", "published", "closed"] = "published"

    @field_validator('company_name', 'description', 'interview_job', 'interview_venue', mode='after')
    def sanitize_fields(cls, v: str) -> str:
        return sanitize_string(v)

class CompanyListingUpdate(BaseModel):
    company_name: Optional[str] = None
    company_email: Optional[EmailStr] = None
    description: Optional[str] = None
    pdf_url: Optional[str] = None
    interview_job: Optional[str] = None
    bond_time: Optional[str] = None
    interview_datetime: Optional[str] = None
    interview_venue: Optional[str] = None
    cgpa_criteria: Optional[float] = None
    status: Optional[Literal["draft", "published", "closed"]] = None

    @field_validator('company_name', 'description', 'interview_job', 'interview_venue', mode='after')
    def sanitize_fields(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            return sanitize_string(v)
        return v

class CompanyListingResponse(BaseModel):
    listing_id: str
    company_name: str
    company_email: str
    description: str
    pdf_url: Optional[str] = None
    interview_job: str
    bond_time: str
    interview_datetime: str
    interview_venue: str
    cgpa_criteria: float
    status: Literal["draft", "published", "closed"]
    posted_by: str
    created_at: datetime
    updated_at: datetime

class SelectionRoundModel(BaseModel):
    round_number: int
    round_name: str

class PlacementPolicyFlagsModel(BaseModel):
    requires_placement_access: bool = True
    requires_placement_eligible: bool = True
    requires_job_interest: bool = True
    requires_internship_interest: bool = True

class CourseBySchoolModel(BaseModel):
    school: str
    course: str

class AdvancedEligibilityModel(BaseModel):
    degree_specializations: List[str] = Field(default_factory=list)
    eligible_courses_by_school: List[CourseBySchoolModel] = Field(default_factory=list)

class DriveModel(BaseModel):
    """
    MongoDB schema for 'drives' collection.
    """
    drive_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    company_name: str
    company_email: Optional[EmailStr] = None
    drive_title: str
    mode: Literal["on_campus", "off_campus", "virtual"] = "on_campus"
    employment_type: Literal["internship", "full_time", "internship_and_full_time"] = "full_time"
    location: str = "Campus"
    school_tag: str = "School of Technology"
    ctc_min: float = 6.0
    ctc_max: float = 12.0
    stipend: Optional[float] = None
    description: str = ""
    key_responsibilities: List[str] = Field(default_factory=list)
    required_skills: List[str] = Field(default_factory=list)
    extracted_required_skills: List[str] = Field(default_factory=list)
    preferred_skills: List[str] = Field(default_factory=list)
    qualifications: str = "B.Tech / BCA"
    additional_requirements: str = ""
    bond_details: str = "No Bond"
    attachment_pdf_url: Optional[str] = None
    eligible_courses: List[str] = Field(default_factory=lambda: ["BTECH_CSE", "BCA", "ALL"])
    eligibility_criteria_summary: str = "Min CGPA 6.0"
    advanced_eligibility: AdvancedEligibilityModel = Field(default_factory=AdvancedEligibilityModel)
    min_cgpa: float = Field(default=6.0, ge=0.0, le=10.0)
    placement_policy_flags: PlacementPolicyFlagsModel = Field(default_factory=PlacementPolicyFlagsModel)
    selection_process: List[SelectionRoundModel] = Field(default_factory=lambda: [
        SelectionRoundModel(round_number=1, round_name="Aptitude Test"),
        SelectionRoundModel(round_number=2, round_name="Technical Round"),
        SelectionRoundModel(round_number=3, round_name="HR Round"),
    ])
    schedule_datetime: str = "To Be Scheduled"
    registration_deadline: str = "Aug 30, 2026"
    status: Literal["draft", "published", "closed"] = "draft"
    offers_made: int = 0
    posted_by: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

class RoundHistoryModel(BaseModel):
    round_number: int
    round_name: str
    result: Literal["pending", "pass", "fail"] = "pending"
    updated_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

class RoundResultUpdate(BaseModel):
    result: Literal["pass", "fail"]
    custom_message: Optional[str] = None

class DriveCreate(BaseModel):
    company_name: str
    company_email: Optional[EmailStr] = None
    drive_title: str
    mode: Literal["on_campus", "off_campus", "virtual"] = "on_campus"
    employment_type: Literal["internship", "full_time", "internship_and_full_time"] = "full_time"
    location: str = "Campus"
    school_tag: str = "School of Technology"
    ctc_min: float = 6.0
    ctc_max: float = 12.0
    stipend: Optional[float] = None
    description: str = ""
    key_responsibilities: List[str] = Field(default_factory=list)
    required_skills: List[str] = Field(default_factory=list)
    extracted_required_skills: List[str] = Field(default_factory=list)
    preferred_skills: List[str] = Field(default_factory=list)
    qualifications: str = "B.Tech / BCA"
    additional_requirements: str = ""
    bond_details: str = "No Bond"
    attachment_pdf_url: Optional[str] = None
    eligible_courses: List[str] = Field(default_factory=lambda: ["BTECH_CSE", "BCA", "ALL"])
    eligibility_criteria_summary: str = "Min CGPA 6.0"
    advanced_eligibility: Optional[AdvancedEligibilityModel] = None
    min_cgpa: float = Field(default=6.0, ge=0.0, le=10.0)
    placement_policy_flags: Optional[PlacementPolicyFlagsModel] = None
    selection_process: Optional[List[SelectionRoundModel]] = None
    schedule_datetime: str
    registration_deadline: str
    status: Literal["draft", "published", "closed"] = "published"

class DriveUpdate(BaseModel):
    company_name: Optional[str] = None
    company_email: Optional[EmailStr] = None
    drive_title: Optional[str] = None
    mode: Optional[Literal["on_campus", "off_campus", "virtual"]] = None
    employment_type: Optional[Literal["internship", "full_time", "internship_and_full_time"]] = None
    location: Optional[str] = None
    school_tag: Optional[str] = None
    ctc_min: Optional[float] = None
    ctc_max: Optional[float] = None
    stipend: Optional[float] = None
    description: Optional[str] = None
    key_responsibilities: Optional[List[str]] = None
    required_skills: Optional[List[str]] = None
    extracted_required_skills: Optional[List[str]] = None
    preferred_skills: Optional[List[str]] = None
    qualifications: Optional[str] = None
    additional_requirements: Optional[str] = None
    bond_details: Optional[str] = None
    attachment_pdf_url: Optional[str] = None
    eligible_courses: Optional[List[str]] = None
    eligibility_criteria_summary: Optional[str] = None
    advanced_eligibility: Optional[AdvancedEligibilityModel] = None
    min_cgpa: Optional[float] = None
    placement_policy_flags: Optional[PlacementPolicyFlagsModel] = None
    selection_process: Optional[List[SelectionRoundModel]] = None
    schedule_datetime: Optional[str] = None
    registration_deadline: Optional[str] = None
    status: Optional[Literal["draft", "published", "closed"]] = None
    offers_made: Optional[int] = None

class DriveResponse(BaseModel):
    drive_id: str
    company_name: str
    drive_title: str
    mode: str
    employment_type: str
    location: str
    school_tag: str
    ctc_min: float
    ctc_max: float
    stipend: Optional[float] = None
    description: str
    key_responsibilities: List[str]
    required_skills: List[str]
    extracted_required_skills: List[str] = Field(default_factory=list)
    preferred_skills: List[str]
    qualifications: str
    additional_requirements: str
    bond_details: str
    attachment_pdf_url: Optional[str] = None
    eligible_courses: List[str]
    eligibility_criteria_summary: str
    advanced_eligibility: dict
    min_cgpa: float
    placement_policy_flags: dict
    selection_process: List[dict]
    schedule_datetime: str
    registration_deadline: str
    status: str
    offers_made: int
    posted_by: str
    created_at: str
    updated_at: str
    is_eligible: Optional[bool] = None
    applicant_count: Optional[int] = None
    eligible_applicant_count: Optional[int] = None

class ApplicationCreate(BaseModel):
    listing_id: Optional[str] = None
    drive_id: Optional[str] = None
    resume_id_used: Optional[str] = None

class ApplicationResponse(BaseModel):
    app_id: str
    student_id: str
    listing_id: Optional[str] = None
    drive_id: Optional[str] = None
    resume_id_used: Optional[str] = None
    status: str
    meets_cgpa_criteria: bool = True
    is_eligible: bool = True
    current_round: int = 0
    final_outcome: str = "in_progress"
    applied_at: datetime


# ---------------------------------------------------------------------------
# 3. Pagination & Lean/Full Optimization DTOs
# ---------------------------------------------------------------------------

class PaginatedResponse(BaseModel, Generic[T]):
    items: List[T]
    page: int
    limit: int
    total_count: int
    has_more: bool

class DriveLeanResponse(BaseModel):
    """
    Lean DTO for student list view (GET /drives).
    Omits heavy fields (description, responsibilities, skills, selection process, attachment PDF).
    """
    drive_id: str
    company_name: str
    drive_title: str
    employment_type: str
    ctc_min: float
    ctc_max: float
    min_cgpa: float
    is_eligible: Optional[bool] = None
    extracted_required_skills: List[str] = Field(default_factory=list)

class MatchingStudentItem(BaseModel):
    """
    Lean DTO for candidate matching recruiter view (GET /recruiter/drives/{drive_id}/matching-students).
    """
    student_id: str
    name: str
    email: Optional[str] = None
    branch: Optional[str] = None
    cgpa: float
    skills: List[str] = Field(default_factory=list)
    matched_skills: List[str] = Field(default_factory=list)
    missing_skills: List[str] = Field(default_factory=list)
    match_count: int = 0
    total_required: int = 0
    resume_url: Optional[str] = None
    has_resume: bool = False

class RecommendedDriveItem(BaseModel):
    """
    Lean DTO for student recommended drives view (GET /drives/recommended).
    """
    drive_id: str
    company_name: str
    drive_title: str
    employment_type: str
    location: str
    ctc_min: float
    ctc_max: float
    min_cgpa: float
    eligible_courses: List[str] = Field(default_factory=list)
    is_eligible: bool = True
    extracted_required_skills: List[str] = Field(default_factory=list)
    matched_skills: List[str] = Field(default_factory=list)
    missing_skills: List[str] = Field(default_factory=list)
    match_count: int = 0
    total_required: int = 0
    match_summary: str = ""

class RecruiterDriveLeanResponse(BaseModel):
    """
    Recruiter list view DTO (GET /recruiter/drives).
    Includes essential metadata and drive overview for recruiter portal cards and bottom sheets.
    """
    drive_id: str
    company_name: str
    drive_title: str
    employment_type: str = "full_time"
    ctc_min: float = 6.0
    ctc_max: float = 12.0
    min_cgpa: float = 6.0
    status: str = "draft"
    created_at: str = ""
    applicant_count: int = 0
    eligible_applicant_count: int = 0
    description: Optional[str] = ""
    location: Optional[str] = ""
    mode: Optional[str] = "on_campus"
    company_email: Optional[str] = ""
    bond_details: Optional[str] = ""
    bond_time: Optional[str] = ""
    schedule_datetime: Optional[str] = ""
    interview_datetime: Optional[str] = ""
    registration_deadline: Optional[str] = ""
    required_skills: List[str] = []
    preferred_skills: List[str] = []
    attachment_pdf_url: Optional[str] = None
    pdf_url: Optional[str] = None

class ApplicantResponse(BaseModel):
    """
    DTO for drive applicants list view (GET /recruiter/drives/{drive_id}/applicants).
    """
    app_id: str
    student_id: str
    drive_id: str
    name: str
    email: Optional[str] = None
    phone_number: Optional[str] = None
    cgpa: float
    course: str
    is_eligible: bool = True
    current_round: int = 0
    round_history: List[dict] = Field(default_factory=list)
    final_outcome: str = "in_progress"
    resume_link: Optional[str] = None
    applied_at: Optional[str] = None

class RecruiterStatsResponse(BaseModel):
    """
    Batched response for GET /recruiter/stats containing all recruiter metrics.
    """
    total_registered_students: int
    total_active_listings: int
    total_active_drives: int
    total_offers_made: int
