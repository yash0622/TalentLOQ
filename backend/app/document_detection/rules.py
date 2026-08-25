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
