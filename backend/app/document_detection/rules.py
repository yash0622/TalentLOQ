"""
Document Type Detection Rules & Scoring Matrix.
Configurable thresholds, regex patterns, keyword dictionaries, and penalties.
"""
import re
from typing import Dict, List, Pattern

# Configurable threshold
RESUME_CONFIDENCE_THRESHOLD = 0.70

# Regex patterns for contact information
EMAIL_REGEX: Pattern = re.compile(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
)
PHONE_REGEX: Pattern = re.compile(
    r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b'
)
URL_REGEX: Pattern = re.compile(
    r'https?://(?:www\.)?(?:linkedin\.com|github\.com|[a-zA-Z0-9-]+\.[a-zA-Z]{2,})[^\s]*',
    re.IGNORECASE
)
DATE_RANGE_REGEX: Pattern = re.compile(
    r'\b(?:19|20)\d{2}\s*[-–—\to]\s*(?:(?:19|20)\d{2}|present|current)\b',
    re.IGNORECASE
)

# Section Header / Keyword Definitions
SECTION_RULES = {
    "contact_info": {
        "weight": 20.0,
        "keywords": ["email", "phone", "mobile", "contact", "address", "linkedin", "github", "portfolio"],
    },
    "education": {
        "weight": 15.0,
        "keywords": [
            "education", "academic profile", "qualification", "qualifications", "degree",
            "b.tech", "m.tech", "b.sc", "b.e", "bca", "mca", "bba", "mba", "university",
            "college", "school", "cgpa", "gpa", "coursework", "graduation"
        ],
    },
    "experience": {
        "weight": 20.0,
        "keywords": [
            "experience", "work experience", "employment", "employment history",
            "work history", "professional experience", "internship", "internships",
            "job title", "responsibilities", "software engineer", "developer", "analyst"
        ],
    },
    "skills": {
        "weight": 15.0,
        "keywords": [
            "skills", "technical skills", "technologies", "programming languages",
            "frameworks", "tools", "competencies", "expertise", "languages"
        ],
    },
    "projects": {
        "weight": 10.0,
        "keywords": [
            "projects", "personal projects", "academic projects", "key projects",
            "developed", "built", "implemented", "repository"
        ],
    },
    "certifications": {
        "weight": 5.0,
        "keywords": [
            "certifications", "certificate", "certified", "awards", "achievements",
            "honors", "accomplishments"
        ],
    },
    "summary": {
        "weight": 10.0,
        "keywords": [
            "summary", "professional summary", "career objective", "objective",
            "profile", "about me", "executive summary"
        ],
    },
    "structure": {
        "weight": 5.0,
        "keywords": [
            "present", "curriculum vitae", "resume", "biodata", "curriculum-vitae"
        ],
    },
}

# Action Verbs common in Resumes
ACTION_VERBS = {
    "developed", "designed", "implemented", "managed", "created", "led", "architected",
    "built", "engineered", "maintained", "collaborated", "optimized", "increased", "reduced"
}

# Negative Indicators / Disqualifiers for non-resume documents
NON_RESUME_DISQUALIFIERS: Dict[str, Dict] = {
    "invoice": {
        "penalty": -50.0,
        "keywords": [
            "invoice", "total due", "bill to", "billing address", "subtotal",
            "tax rate", "invoice number", "invoice date", "payment terms", "amount payable"
        ],
    },
    "research_paper": {
        "penalty": -40.0,
        "keywords": [
            "abstract", "ieee", "arxiv", "bibliography", "figure 1:", "table 1:",
            "doi:", "journal of", "conference on", "et al."
        ],
    },
    "assignment": {
        "penalty": -40.0,
        "keywords": [
            "assignment 1", "assignment 2", "homework", "syllabus", "course code",
            "question 1", "deadline:", "instructor:", "submission link"
        ],
    },
    "legal": {
        "penalty": -50.0,
        "keywords": [
            "minutes of meeting", "whereas", "hereto", "clause", "party of the first part",
            "witnesseth", "jurisdiction", "indemnify", "agreement hereby"
        ],
    },
    "standalone_certificate": {
        "penalty": -35.0,
        "keywords": [
            "this is to certify that", "has successfully completed", "certificate of completion",
            "authorized signature", "issued on"
        ],
    },
}

# ---------------------------------------------------------------------------
# Marksheet Classification Rules & Keywords
# ---------------------------------------------------------------------------

TENTH_MARKSHEET_KEYWORDS = [
    "secondary school", "class x", "class 10", "ssc", "matriculation",
    "high school certificate", "10th", "std x", "standard x", "standard 10",
    "board of secondary education", "secondary school certificate", "cbse 10",
    "gseb ssc", "icse", "indian certificate of secondary education",
    "high school examination", "secondary examination"
]

TWELFTH_MARKSHEET_KEYWORDS = [
    "higher secondary", "class xii", "class 12", "hsc", "intermediate",
    "senior school certificate", "12th", "std xii", "standard xii", "standard 12",
    "senior secondary", "higher secondary certificate", "pre-university",
    "puc", "isc", "indian school certificate", "intermediate examination"
]

DIPLOMA_MARKSHEET_KEYWORDS = [
    "diploma", "polytechnic", "diploma in engineering", "board of technical examinations",
    "state board of technical education", "gtu diploma", "directorate of technical education",
    "diploma examination", "diploma in computer", "diploma in mechanical"
]

UG_MARKSHEET_KEYWORDS = [
    "grade card", "grade sheet", "transcript", "statement of marks", "grade report",
    "sgpa", "cgpa", "semester", "end semester", "bachelor of technology", "b.tech",
    "b.e.", "bca", "b.sc", "bachelor of engineering", "university examination",
    "provisional grade report", "gsfc university", "credits earned", "course code",
    "grade points", "semester grade point"
]

# Regex patterns for Marksheet extraction
PERCENTAGE_REGEX: Pattern = re.compile(
    r'(?:percentage|percent|aggregate|pct|%\s*marks?|scored\s*:?)(?:\s*\([^\)]*\))?\s*[:=]?\s*([0-9]{1,3}(?:\.[0-9]{1,3})?)\s*%?',
    re.IGNORECASE
)

RAW_PERCENTAGE_REGEX: Pattern = re.compile(
    r'\b([3-9][0-9]\.[0-9]{1,2})\s*%?',
    re.IGNORECASE
)

CGPA_REGEX: Pattern = re.compile(
    r'(?:cgpa|c\.g\.p\.a\.?|cpi|c\.p\.i\.?|cumulative\s*grade\s*point\s*average|cumulative\s*performance\s*index|cumulative\s*gpa|overall\s*cgpa|overall\s*gpa|final\s*cgpa|final\s*gpa)(?:\s*\([^\)]*\))?\s*(?:of|is|[:=])?\s*([0-9]\.[0-9]{1,2}|10(?:\.0{1,2})?)',
    re.IGNORECASE
)

SGPA_REGEX: Pattern = re.compile(
    r'(?:sgpa|s\.g\.p\.a\.?|spi|s\.p\.i\.?|semester\s*grade\s*point\s*average|semester\s*performance\s*index|semester\s*gpa|current\s*spi|current\s*sgpa)(?:\s*\([^\)]*\))?\s*(?:of|is|[:=])?\s*([0-9]\.[0-9]{1,2}|10(?:\.0{1,2})?)',
    re.IGNORECASE
)

PASSING_YEAR_REGEX: Pattern = re.compile(
    r'(?:passing\s*year|year\s*of\s*passing|passed\s*in|session|year\s*:?|exam\s*date)\s*[:=]?\s*(20[0-2][0-9]|199[0-9])',
    re.IGNORECASE
)

ENROLLMENT_REGEX: Pattern = re.compile(
    r'(?:enrollm[eaor]+nt|enrolment|roll|reg(?:istration)?|seat)\s*(?:no\.?|numb[eaor]+)?\s*[:=]?\s*([A-Za-z0-9\-_/]{5,25})',
    re.IGNORECASE
)

BACKLOG_PATTERNS = [
    # Explicit 0 / cleared backlog patterns
    (re.compile(r'(?:active\s*)?backlogs?\s*[:=]?\s*(?:0|zero|nil|none|no\b)', re.IGNORECASE), 0),
    (re.compile(r'\bno\s+active\s+backlogs?\b', re.IGNORECASE), 0),
    (re.compile(r'\batkt\s*[:=]?\s*(?:0|zero|nil|none|no\b)', re.IGNORECASE), 0),
    (re.compile(r'\bcleared\s+all\s+subjects?\b', re.IGNORECASE), 0),
    (re.compile(r'\bpass(?:\s+with\s+distinction|\s+first\s+class)?\b', re.IGNORECASE), 0),
    # Numerical backlog patterns
    (re.compile(r'(?:active\s*)?backlogs?\s*[:=]?\s*([1-9][0-9]?)', re.IGNORECASE), None),
    (re.compile(r'\batkt\s*[:=]?\s*([1-9][0-9]?)', re.IGNORECASE), None),
    (re.compile(r'(?:current\s*)?arrears?\s*[:=]?\s*([1-9][0-9]?)', re.IGNORECASE), None),
    (re.compile(r'(?:failed\s*courses?|failed\s*subjects?)\s*[:=]?\s*([1-9][0-9]?)', re.IGNORECASE), None),
]

