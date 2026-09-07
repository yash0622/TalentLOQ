"""
Modular Parsers for Academic & Professional Documents.
Supports:
- Resume (Skills normalization, Known Languages, Candidate Name)
- 10th Marksheet (Name, Board, Passing Year, Percentage)
- 12th / Diploma Marksheet (Subtype detection, Board/University, Year, Percentage or CGPA)
- Current UG Marksheet (University, Enrollment No, Branch, Semester, SGPA, CGPA, Backlogs / ATKT / UNKNOWN)
"""
import re
import difflib
import logging
from typing import Dict, Any, List, Optional, Tuple
from .rules import (
    PERCENTAGE_REGEX,
    RAW_PERCENTAGE_REGEX,
    CGPA_REGEX,
    SGPA_REGEX,
    PASSING_YEAR_REGEX,
    ENROLLMENT_REGEX,
    BACKLOG_PATTERNS,
)
from .marks_table_extractor import MarksTableExtractor

# Standard Normalized Tech Skills Dictionary (canonical casing)
CANONICAL_SKILLS_MAP: Dict[str, str] = {
    "python": "Python",
    "python3": "Python",
    "java": "Java",
    "c++": "C++",
    "cpp": "C++",
    "c#": "C#",
    "c language": "C",
    "c programming": "C",
    "javascript": "JavaScript",
    "js": "JavaScript",
    "typescript": "TypeScript",
    "ts": "TypeScript",
    "dart": "Dart",
    "flutter": "Flutter",
    "react": "React",
    "react.js": "React",
    "reactjs": "React",
    "angular": "Angular",
    "vue": "Vue.js",
    "vue.js": "Vue.js",
    "node": "Node.js",
    "node.js": "Node.js",
    "nodejs": "Node.js",
    "fastapi": "FastAPI",
    "django": "Django",
    "flask": "Flask",
    "spring": "Spring Boot",
    "spring boot": "Spring Boot",
    "sql": "SQL",
    "postgresql": "PostgreSQL",
    "postgres": "PostgreSQL",
    "mysql": "MySQL",
    "mongodb": "MongoDB",
    "redis": "Redis",
    "docker": "Docker",
    "kubernetes": "Kubernetes",
    "k8s": "Kubernetes",
    "aws": "AWS",
    "azure": "Azure",
    "gcp": "GCP",
    "git": "Git",
    "github": "GitHub",
    "html": "HTML5",
    "html5": "HTML5",
    "css": "CSS3",
    "css3": "CSS3",
    "machine learning": "Machine Learning",
    "ml": "Machine Learning",
    "deep learning": "Deep Learning",
    "ai": "Artificial Intelligence",
    "artificial intelligence": "Artificial Intelligence",
    "nlp": "NLP",
    "data science": "Data Science",
    "pandas": "Pandas",
    "numpy": "NumPy",
    "linux": "Linux",
    "rest api": "REST APIs",
    "graphql": "GraphQL",
    "tailwind": "Tailwind CSS",
    "tailwindcss": "Tailwind CSS",
    "pytorch": "PyTorch",
    "firebase": "Firebase",
    "firestore": "Cloud Firestore",
    "rag": "RAG",
    "llm": "LLMs",
    "llms": "LLMs",
    "pytest": "Pytest",
    "websockets": "WebSockets",
    "websocket": "WebSockets",
    "computer vision": "Computer Vision",
    "cnn": "CNNs",
    "cnns": "CNNs",
    "lstm": "LSTM",
    "autoencoder": "Autoencoders",
    "autoencoders": "Autoencoders",
    "multi-agent": "Multi-Agent Frameworks",
    "multi-agent frameworks": "Multi-Agent Frameworks",
    "prompt engineering": "Prompt Engineering",
    "vector search": "Vector Search",
    "deepseek": "DeepSeek",
    "mistral": "Mistral API",
    "gemini": "Gemini Flash",
    "openrouter": "OpenRouter",
}

# Standard Normalized Soft Skills Dictionary (canonical casing)
CANONICAL_SOFT_SKILLS_MAP: Dict[str, str] = {
    "problem solving": "Problem Solving",
    "critical thinking": "Critical Thinking",
    "communication": "Communication",
    "teamwork": "Teamwork",
    "team leadership": "Team Leadership",
    "leadership": "Leadership",
    "collaboration": "Collaboration",
    "time management": "Time Management",
    "adaptability": "Adaptability",
    "agile": "Agile",
    "scrum": "Scrum",
    "creative thinking": "Creative Thinking",
    "decision making": "Decision Making",
    "interpersonal skills": "Interpersonal Skills",
    "work ethic": "Work Ethic",
    "public speaking": "Public Speaking",
    "analytical thinking": "Analytical Thinking",
}

# Known Programming Languages subset for language classification
PROGRAMMING_LANGUAGES_LIST: List[str] = [
    "Python", "Java", "C++", "C", "C#", "JavaScript", "TypeScript",
    "Dart", "Go", "Rust", "Kotlin", "Swift", "PHP", "Ruby", "SQL", "R", "Scala", "HTML5", "CSS3"
]

# Known Natural / Spoken Languages
KNOWN_LANGUAGES = [
    "English", "Hindi", "Gujarati", "Marathi", "Tamil", "Telugu",
    "Kannada", "Malayalam", "Bengali", "Punjabi", "Spanish",
    "French", "German", "Japanese", "Mandarin", "Russian"
]

# Educational Boards
KNOWN_BOARDS = [
    ("CBSE", "Central Board of Secondary Education (CBSE)"),
    ("GUJARAT SECONDARY", "Gujarat Secondary and Higher Secondary Education Board (GSEB)"),
    ("GSHEB", "Gujarat Secondary and Higher Secondary Education Board (GSEB)"),
    ("GSEB", "Gujarat Secondary and Higher Secondary Education Board (GSEB)"),
    ("GUJARAT BOARD", "Gujarat Secondary and Higher Secondary Education Board (GSEB)"),
    ("ICSE", "Council for the Indian School Certificate Examinations (ICSE)"),
    ("ISC", "Indian School Certificate (ISC)"),
    ("STATE BOARD", "State Board of Secondary Education"),
    ("GTU", "Gujarat Technological University (GTU)"),
    ("GSFC", "GSFC University"),
]

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# University / Course / Branch Detection Tables (first match wins)
# ---------------------------------------------------------------------------

UNIVERSITY_MAP = [
    ("gsfc", "GSFC University"),
    ("gujarat technological", "Gujarat Technological University"),
    ("gtu", "Gujarat Technological University"),
    ("nirma", "Nirma University"),
    ("parul", "Parul University"),
    ("maharaja sayajirao", "The Maharaja Sayajirao University of Baroda"),
    ("msu baroda", "The Maharaja Sayajirao University of Baroda"),
    ("msu", "The Maharaja Sayajirao University of Baroda"),
    ("charusat", "Charotar University of Science & Technology"),
    ("ganpat", "Ganpat University"),
    ("lj university", "LJ University"),
    ("marwadi", "Marwadi University"),
    ("indus university", "Indus University"),
    ("silver oak", "Silver Oak University"),
    ("uka tarsadia", "Uka Tarsadia University"),
    ("dharmsinh desai", "Dharmsinh Desai University"),
    ("ddu", "Dharmsinh Desai University"),
    ("sardar patel", "Sardar Patel University"),
    ("spu", "Sardar Patel University"),
    ("gujarat university", "Gujarat University"),
    ("kadi sarva", "Kadi Sarva Vishwavidyalaya"),
    ("itm (sls)", "ITM (SLS) Baroda University"),
    ("itm baroda", "ITM (SLS) Baroda University"),
    ("itm university", "ITM (SLS) Baroda University"),
    ("itm", "ITM (SLS) Baroda University"),
]


def fuzzy_match_skill(word: str, canonical_map: Dict[str, str], threshold: float = 0.88) -> Optional[str]:
    """
    Fuzzy matches a single word/token against the canonical skills map.
    Skips short tokens (< 4 chars) to prevent false positives with short keywords like 'c', 'r', 'go'.
    """
    w_low = word.lower().strip()
    if not w_low:
        return None
    if w_low in canonical_map:
        return canonical_map[w_low]
    if len(w_low) < 4:
        return None

    for key, canonical in canonical_map.items():
        if abs(len(key) - len(w_low)) <= 2:
            ratio = difflib.SequenceMatcher(None, w_low, key).ratio()
            if ratio >= threshold:
                return canonical
    return None


def fuzzy_match_institution(text: str, known_institutions: List[Tuple[str, str]], threshold: float = 0.80) -> Optional[str]:
    """
    Fuzzy matches an institution name (board or university) against known aliases.
    """
    t_low = text.lower()
    # 1. Exact substring check first
    for alias, canonical in known_institutions:
        if alias.lower() in t_low:
            return canonical

    # 2. Line-by-line fuzzy matching
    for line in t_low.split("\n"):
        clean_line = line.strip()
        if len(clean_line) < 5:
            continue
        for alias, canonical in known_institutions:
            a_low = alias.lower()
            if len(a_low) >= 5:
                ratio = difflib.SequenceMatcher(None, clean_line[:len(a_low) + 6], a_low).ratio()
                if ratio >= threshold:
                    return canonical
    return None

COURSE_MAP = [
    ("bachelor of technology", "B.Tech"), ("b.tech", "B.Tech"),
    ("bachelor of engineering", "B.E."), ("b.e.", "B.E."),
    ("master of technology", "M.Tech"), ("m.tech", "M.Tech"),
    ("master of computer applications", "MCA"), ("mca", "MCA"),
    ("bachelor of computer applications", "BCA"), ("bca", "BCA"),
    ("bachelor of science", "B.Sc"), ("b.sc", "B.Sc"),
    ("master of science", "M.Sc"), ("m.sc", "M.Sc"),
    ("master of business administration", "MBA"), ("mba", "MBA"),
    ("bachelor of business administration", "BBA"), ("bba", "BBA"),
    ("bachelor of pharmacy", "B.Pharm"), ("b.pharm", "B.Pharm"),
]

BRANCH_MAP = [
    ("computer science", "Computer Science & Engineering"),
    ("computer engineering", "Computer Science & Engineering"),
    ("information technology", "Information Technology"),
    ("electronics and communication", "Electronics & Communication Engineering"),
    ("electronics & communication", "Electronics & Communication Engineering"),
    ("electrical and electronics", "Electrical & Electronics Engineering"),
    ("electrical engineering", "Electrical Engineering"),
    ("civil engineering", "Civil Engineering"),
    ("mechanical engineering", "Mechanical Engineering"),
    ("chemical engineering", "Chemical Engineering"),
    ("fire and safety", "Fire & Safety Engineering"),
    ("fire & safety", "Fire & Safety Engineering"),
    ("data science", "Data Science"),
    ("artificial intelligence", "Artificial Intelligence & ML"),
    ("biotechnology", "Biotechnology"),
    ("automobile", "Automobile Engineering"),
    ("aerospace", "Aerospace Engineering"),
    ("biomedical", "Biomedical Engineering"),
    ("environmental", "Environmental Engineering"),
]

# ---------------------------------------------------------------------------
# OCR Pre-processing
# ---------------------------------------------------------------------------

_OCR_CORRECTIONS = {
    "rosult": "Result", "crodits": "Credits", "semostar": "Semester",
    "semestor": "Semester", "porcentage": "Percentage", "percantage": "Percentage",
    "studont": "Student", "enrollmont": "Enrollment", "numbor": "Number",
    "univorsity": "University", "enginoering": "Engineering", "bacholor": "Bachelor",
    "tochnology": "Technology", "cortificate": "Certificate", "socondary": "Secondary",
    "examinotion": "Examination", "markshoot": "Marksheet", "obtainod": "Obtained",
}

_SKILL_NOISE_WORDS = frozenset({
    # Common English
    "the", "and", "for", "with", "from", "that", "this", "have", "been", "will",
    "work", "used", "using", "also", "such", "more", "than", "into", "each",
    "make", "made", "like", "well", "good", "best", "new", "year", "years",
    "team", "role", "based", "level", "high", "low", "end", "part", "full",
    "time", "real", "system", "systems", "strong", "various", "ability",
    # Resume action verbs
    "developed", "designed", "implemented", "managed", "created", "built",
    "led", "maintained", "collaborated", "optimized", "increased", "reduced",
    "established", "delivered", "achieved", "streamlined", "contributed",
    # Academic / location
    "university", "college", "school", "board", "institute", "department",
    "city", "state", "india", "gujarat", "ahmedabad", "vadodara", "baroda",
    "mumbai", "delhi", "pune", "bangalore", "chennai", "hyderabad", "kolkata",
    "currently", "working", "worked", "present", "company", "organization",
    "intern", "internship", "trainee", "fresher",
    # Months
    "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
    "january", "february", "march", "april", "june", "july", "august",
    "september", "october", "november", "december",
    # Resume section names
    "experience", "education", "project", "projects", "objective", "summary",
    "reference", "references", "hobbies", "interests", "declaration",
    "personal", "details", "profile", "achievements", "activities",
})


def _normalize_ocr_text(text: str) -> str:
    """Pre-process OCR text: fix common misspellings, digit substitutions, normalize whitespace."""
    for wrong, right in _OCR_CORRECTIONS.items():
        text = re.sub(re.escape(wrong), right, text, flags=re.IGNORECASE)

    # OCR digit-letter repairs in 4-digit years (e.g. 2O24 -> 2024, 202O -> 2020, 20O4 -> 2004)
    text = re.sub(r'\b2[oO](\d{2})\b', r'20\1', text)
    text = re.sub(r'\b(19|20)[oO](\d)\b', r'\g<1>0\g<2>', text)
    text = re.sub(r'\b(19|20)(\d)[oO]\b', r'\g<1>\g<2>0', text)

    # Decimal OCR repairs for CGPA / SGPA / Percentage (e.g. 7.l3 -> 7.13, 85.l0 -> 85.10, 8.O -> 8.0, 7.9l -> 7.91)
    text = re.sub(r'(?<=\d\.)[oO]', '0', text)
    text = re.sub(r'(?<=\d\.)[lI|]', '1', text)
    text = re.sub(r'(?<=\d\.\d)[lI|]', '1', text)
    text = re.sub(r'(?<=\d\.\d)[oO]', '0', text)

    # Fix OCR spaced decimals like "7 . 13" or comma decimals like "7,13" in GPA context
    text = re.sub(r'\b([0-9]{1,2})\s*[\.,]\s*([0-9]{1,2})\b', r'\1.\2', text)

    # Collapse multiple spaces/tabs to single space (preserve newlines)
    text = re.sub(r'[^\S\n]+', ' ', text)
    return text


class BaseParser:
    @staticmethod
    def extract_name_from_lines(lines: List[str], profile_name: Optional[str] = None) -> Optional[str]:
        """Heuristic extractor for student name from top lines, certify clauses, or name labels."""
        ignore_keywords = [
            "resume", "curriculum", "vitae", "marksheet", "board", "university", "unersity", "certificate",
            "examination", "statement", "secondary", "certify", "ccrtify", "chis is", "this is",
            "wing", "centre", "school", "seat", "index", "candidate", "student", "obtained",
            "grand total", "result", "grade", "percentage", "subject", "baroda", "vadodara",
            "gujarat", "india", "governing", "council", "academic", "college", "faculty",
            "department", "institute", "technology", "engineering", "sciences", "think", "beyond",
            "president", "provost", "enrolment", "enrollment", "first class", "distinction",
            "contact", "email", "phone", "mobile", "address", "github", "linkedin", "portfolio",
            "project", "skills", "experience", "education", "summary", "objective"
        ]

        # 0. If profile_name is known, check if it or its tokens appear in the first 8 lines
        if profile_name:
            norm_profile = "".join(c for c in profile_name.lower() if c.isalnum() or c.isspace()).strip()
            profile_tokens = [t for t in norm_profile.split() if len(t) >= 3]
            for line in lines[:8]:
                l_clean = "".join(c for c in line.lower() if c.isalnum() or c.isspace()).strip()
                if norm_profile in l_clean or (profile_tokens and all(t in l_clean.split() for t in profile_tokens)):
                    return profile_name.title()

        # 1. Positional Header Scan in top 6 lines (Resumes & Documents almost always place candidate name here)
        for i, line in enumerate(lines[:6]):
            clean = line.strip()
            clean_lower = clean.lower()
            if any(k in clean_lower for k in ignore_keywords) or "@" in clean or "http" in clean_lower or "+91" in clean or any(c.isdigit() for c in clean):
                continue
            if re.match(r'^[A-Za-z\s\.]+$', clean) and 1 <= len(clean.split()) <= 4:
                if not any(w in clean_lower for w in ["world", "robotized", "system", "app", "application", "developer", "engineer"]):
                    return clean.title()

        # 2. Check certify clauses (very common in Indian diplomas & degree certificates)
        for i, line in enumerate(lines):
            l_lower = line.lower()
            if any(p in l_lower for p in ["hereby certifies", "certifies that", "to certify that", "certify that", "conferred upon"]):
                if i + 1 < len(lines):
                    next_l = lines[i + 1].strip()
                    if re.match(r'^[A-Za-z\s\.]+$', next_l) and len(next_l.split()) >= 2:
                        return next_l.title()

        # 3. Check explicit name labels (Must NOT be project name, company name, domain name, etc.)
        for i, line in enumerate(lines):
            line_str = line.strip()
            # If label is on its own line (e.g. "Student Name\nSHARMA CHINTAN INDRAVADAN")
            if re.match(r'^(?:student|studont|candidate)\s*name$', line_str, re.IGNORECASE) and i + 1 < len(lines):
                next_l = lines[i + 1].strip()
                if re.match(r'^[A-Za-z\s\.]+$', next_l) and len(next_l.split()) >= 2:
                    return next_l.title()

            m = re.search(r'(?<!project\s)(?<!company\s)(?<!org\s)(?<!domain\s)(?<!app\s)(?<!firm\s)(?<!tool\s)(?<!repo\s)(?:candidate\s*name|student\s*name|name\s*of\s*candidate|full\s*name)\s*[:=]\s*([A-Za-z\s\.]{3,50})', line_str, re.IGNORECASE)
            if m:
                name_cand = m.group(1).strip()
                if len(name_cand.split()) >= 1 and not any(k in name_cand.lower() for k in ["examination", "board", "marks", "university", "school", "certify", "project", "world", "robotized"]):
                    return name_cand.title()

        # 4. Positional fallback in top 18 lines
        for i, line in enumerate(lines[:18]):
            clean = line.strip()
            clean_lower = clean.lower()
            if any(k in clean_lower for k in ignore_keywords) or "@" in clean or "http" in clean_lower or any(c.isdigit() for c in clean):
                continue
            if re.match(r'^[A-Za-z\s\.]+$', clean) and len(clean.split()) >= 2:
                if not any(w in clean_lower for w in ["world", "robotized", "system", "app"]):
                    return clean.title()

        return None


class ResumeParser(BaseParser):
    @staticmethod
    def _is_valid_skill_token(token: str) -> bool:
        """Validate dynamic skill candidate: reject noise, institutions, ordinals, course codes, degrees."""
        if not (2 <= len(token) <= 30):
            return False
        if token.isdigit():
            return False
        lower = token.lower()
        if lower in _SKILL_NOISE_WORDS:
            return False
        # Reject ordinals / grade years like "3rd year", "1st sem", "10th"
        if re.match(r'^\d+(?:st|nd|rd|th)\b', lower):
            return False
        # Reject course codes like "CS101", "ME202"
        if re.match(r'^[a-z]{2,4}\s*\d{2,4}$', lower):
            return False
        # Reject organizational and academic boilerplate words
        org_words = ("school", "college", "university", "institute", "ltd", "pvt", "inc", "corp", "department", "semester", "academic")
        if any(w in lower for w in org_words):
            return False
        # Reject academic degrees leaking into skills
        if re.search(r'\b(?:b\.?tech|m\.?tech|bca|mca|b\.?sc|m\.?sc|b\.?e|mba|bba|diploma)\b', lower):
            return False
        # Phrases of 4+ words that are not recognized canonical skills are noise
        if len(token.split()) >= 4:
            return False
        return True

    @classmethod
    def parse(cls, text: str, profile_name: Optional[str] = None) -> Dict[str, Any]:
        text = _normalize_ocr_text(text)
        lines = [line.strip() for line in text.split("\n") if line.strip()]
        text_lower = text.lower()

        name = cls.extract_name_from_lines(lines, profile_name=profile_name)

        tech_skills_found = set()
        for raw_token, canonical in CANONICAL_SKILLS_MAP.items():
            pattern = r'\b' + re.escape(raw_token) + r'\b'
            if re.search(pattern, text_lower):
                tech_skills_found.add(canonical)

        soft_skills_found = set()
        for raw_token, canonical in CANONICAL_SOFT_SKILLS_MAP.items():
            pattern = r'\b' + re.escape(raw_token) + r'\b'
            if re.search(pattern, text_lower):
                soft_skills_found.add(canonical)

        # Dynamic Section Extraction: parse skills directly from TECHNICAL / SOFT SKILLS blocks
        sec_match = re.search(
            r'(?:technical\s*skills|soft\s*skills|key\s*skills|skills|competencies)\s*[:\n](.+?)(?:\n\s*(?:professional\s*experience|work\s*experience|experience|projects|education|certifications|publications|languages\s*known|known\s*languages|spoken\s*languages|languages)\b|\Z)',
            text,
            re.IGNORECASE | re.DOTALL,
        )
        if sec_match:
            sec_text = sec_match.group(1)
            for line in sec_text.split("\n"):
                line_clean = line.strip()
                if not line_clean:
                    continue
                if ":" in line_clean:
                    _, items_str = line_clean.split(":", 1)
                else:
                    items_str = line_clean
                items_str = items_str.replace("(", ",").replace(")", "")
                tokens = [t.strip(" ,;()•-·\t\r") for t in re.split(r'[,|•·]', items_str)]
                for tok in tokens:
                    base_tok = re.sub(r'\s+v?\d+(?:\.\d+)*\w*', '', tok).strip()
                    if not base_tok:
                        continue
                    base_lower = base_tok.lower()
                    if base_tok in KNOWN_LANGUAGES or any(h in base_lower for h in ["languages known", "known languages", "soft skills", "technical skills"]):
                        continue
                    if base_lower in CANONICAL_SKILLS_MAP:
                        tech_skills_found.add(CANONICAL_SKILLS_MAP[base_lower])
                    elif base_lower in CANONICAL_SOFT_SKILLS_MAP:
                        soft_skills_found.add(CANONICAL_SOFT_SKILLS_MAP[base_lower])
                    else:
                        f_tech = fuzzy_match_skill(base_tok, CANONICAL_SKILLS_MAP)
                        if f_tech:
                            tech_skills_found.add(f_tech)
                        else:
                            f_soft = fuzzy_match_skill(base_tok, CANONICAL_SOFT_SKILLS_MAP)
                            if f_soft:
                                soft_skills_found.add(f_soft)
                            elif cls._is_valid_skill_token(base_tok):
                                tech_skills_found.add(base_tok)

        # Known Spoken Languages
        languages_found = set()
        lang_section_match = re.search(
            r'(?:spoken\s*languages|languages\s*known|known\s*languages|(?<!programming\s)languages)\s*[:\n](.+?)(?:\n\s*\n|\Z)',
            text,
            re.IGNORECASE | re.DOTALL,
        )
        lang_search = lang_section_match.group(1) if lang_section_match else text

        for lang in KNOWN_LANGUAGES:
            if re.search(r'\b' + re.escape(lang) + r'\b', lang_search, re.IGNORECASE):
                languages_found.add(lang)

        # Programming Languages identified from tech skills & text
        prog_languages_found = set()
        for p_lang in PROGRAMMING_LANGUAGES_LIST:
            if p_lang in tech_skills_found or re.search(r'\b' + re.escape(p_lang.lower()) + r'\b', text_lower):
                prog_languages_found.add(p_lang)

        # Professional, Portfolio & Coding Platform Links
        social_links: Dict[str, str] = {}
        link_patterns = [
            ("linkedin", re.compile(r'(?:https?://)?(?:www\.)?linkedin\.com/in/([a-zA-Z0-9_\-\.]+)', re.I)),
            ("github", re.compile(r'(?:https?://)?(?:www\.)?github\.com/([a-zA-Z0-9_\-\.]+)', re.I)),
            ("leetcode", re.compile(r'(?:https?://)?(?:www\.)?leetcode\.com/(?:u/)?([a-zA-Z0-9_\-\.]+)', re.I)),
            ("codeforces", re.compile(r'(?:https?://)?(?:www\.)?codeforces\.com/profile/([a-zA-Z0-9_\-\.]+)', re.I)),
            ("codechef", re.compile(r'(?:https?://)?(?:www\.)?codechef\.com/users/([a-zA-Z0-9_]+)', re.I)),
            ("hackerrank", re.compile(r'(?:https?://)?(?:www\.)?hackerrank\.com/(?:profile/)?([a-zA-Z0-9_]+)', re.I)),
            ("kaggle", re.compile(r'(?:https?://)?(?:www\.)?kaggle\.com/([a-zA-Z0-9_]+)', re.I)),
            ("geeksforgeeks", re.compile(r'(?:https?://)?(?:www\.)?(?:auth\.)?geeksforgeeks\.org/user/([a-zA-Z0-9_]+)', re.I)),
            ("twitter", re.compile(r'(?:https?://)?(?:www\.)?(?:twitter\.com|x\.com)/([a-zA-Z0-9_]+)', re.I)),
        ]

        github_reserved = {"features", "pricing", "topics", "collections", "trending", "explore", "about", "contact"}
        for platform, pattern in link_patterns:
            m = pattern.search(text)
            if m:
                matched_user = m.group(1).rstrip("./,);:")
                if platform == "github" and matched_user.lower() in github_reserved:
                    continue
                raw_url = m.group(0).rstrip("./,);:")
                if not raw_url.startswith("http://") and not raw_url.startswith("https://"):
                    raw_url = f"https://{raw_url}"
                social_links[platform] = raw_url

        # Portfolio / Personal Website extraction
        portfolio_match = re.search(r'(?:portfolio|website|personal\s*site|web)\s*[:\-\s]\s*(https?://[^\s,;|]+)', text, re.I)
        if not portfolio_match:
            portfolio_match = re.search(r'https?://(?:www\.)?([a-zA-Z0-9-]+\.(?:github\.io|vercel\.app|netlify\.app|me|dev))[^\s,;|]*', text, re.I)
        if portfolio_match:
            port_url = portfolio_match.group(1) if portfolio_match.lastindex and portfolio_match.lastindex >= 1 else portfolio_match.group(0)
            port_url = port_url.rstrip("./,);:")
            if not port_url.startswith("http://") and not port_url.startswith("https://"):
                port_url = f"https://{port_url}"
            social_links["portfolio"] = port_url

        # Deployment & DevOps Skills identification
        DEPLOYMENT_KEYWORDS = {
            "docker": "Docker",
            "kubernetes": "Kubernetes",
            "k8s": "Kubernetes",
            "aws": "AWS",
            "amazon web services": "AWS",
            "gcp": "Google Cloud Platform",
            "google cloud": "Google Cloud Platform",
            "azure": "Microsoft Azure",
            "ci/cd": "CI/CD",
            "cicd": "CI/CD",
            "github actions": "GitHub Actions",
            "jenkins": "Jenkins",
            "nginx": "Nginx",
            "linux": "Linux",
            "vercel": "Vercel",
            "netlify": "Netlify",
            "terraform": "Terraform",
            "ansible": "Ansible",
            "helm": "Helm",
            "cloudflare": "Cloudflare",
            "heroku": "Heroku",
            "prometheus": "Prometheus",
            "grafana": "Grafana",
        }
        deployment_skills_found = set()
        for kw, canonical_dep in DEPLOYMENT_KEYWORDS.items():
            if re.search(r'\b' + re.escape(kw) + r'\b', text_lower):
                deployment_skills_found.add(canonical_dep)

        # Internships & Work Experience Extraction
        internships: List[Dict[str, Any]] = []
        exp_section_match = re.search(
            r'(?:internships?|work\s*experience|professional\s*experience|industrial\s*training|practical\s*training)\s*[:\n](.+?)(?:\n\s*(?:education|projects|technical\s*skills|skills|certifications|publications|languages|achievements|declaration)\b|\Z)',
            text,
            re.IGNORECASE | re.DOTALL,
        )

        search_exp_text = exp_section_match.group(1) if exp_section_match else text

        # Parse distinct internship blocks by scanning role patterns and duration patterns
        entry_patterns = re.finditer(
            r'(?:(?:^|\n)\s*([A-Za-z0-9\s,\.&]{3,45}?)\s+(?:at|@|[-–|•])\s+([A-Za-z0-9\s,\.&]{2,45}?)\s*(?:\n|\(|\||\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|\d{4})\b))',
            search_exp_text,
            re.IGNORECASE
        )

        seen_companies = set()
        for ep in entry_patterns:
            part1 = ep.group(1).strip()
            part2 = ep.group(2).strip()
            # Decide which part is role and which is company
            combined = f"{part1} {part2}".lower()
            if any(term in combined for term in ["intern", "trainee", "developer", "engineer", "assistant", "lead", "analyst", "fellow"]):
                role = part1 if any(t in part1.lower() for t in ["intern", "trainee", "developer", "engineer", "analyst"]) else part2
                comp = part2 if role == part1 else part1
                comp_clean = re.sub(r'[^A-Za-z0-9\s]', '', comp).strip()
                if len(comp_clean) >= 2 and comp_clean.lower() not in seen_companies and not any(ign in comp_clean.lower() for ign in ["experience", "education", "project", "university"]):
                    seen_companies.add(comp_clean.lower())
                    internships.append({
                        "company_name": comp.title(),
                        "role_title": role.title(),
                        "duration": "Reported in Resume",
                        "description": f"{role.title()} at {comp.title()}"
                    })

        # Fallback count: Scan for occurrences of "intern" / "internship" with date ranges or distinct companies
        if not internships:
            intern_mentions = re.findall(r'\b([A-Za-z\s]{3,30})\s+intern(?:ship)?\b', search_exp_text, re.IGNORECASE)
            for m in intern_mentions[:4]:
                clean_m = m.strip().title()
                if len(clean_m) >= 3 and clean_m.lower() not in seen_companies and not any(w in clean_m.lower() for w in ["summer", "winter", "an", "the", "as", "seeking"]):
                    seen_companies.add(clean_m.lower())
                    internships.append({
                        "company_name": clean_m,
                        "role_title": "Intern",
                        "duration": "Completed",
                        "description": f"Internship at {clean_m}"
                    })

        internship_count = len(internships)
        # Check if text explicitly says e.g. "Completed 2 internships" or "2+ internships"
        num_match = re.search(r'\b(\d+)\+?\s*internships?\b', text_lower)
        if num_match:
            try:
                explicit_cnt = int(num_match.group(1))
                if explicit_cnt > internship_count:
                    internship_count = explicit_cnt
            except Exception:
                pass

        result = {
            "candidate_name": name,
            "skills": sorted(list(tech_skills_found.union(soft_skills_found))),
            "technical_skills": sorted(list(tech_skills_found)),
            "soft_skills": sorted(list(soft_skills_found)),
            "deployment_skills": sorted(list(deployment_skills_found)),
            "internships": internships,
            "internship_count": internship_count,
            "languages": sorted(list(languages_found)),
            "spoken_languages": sorted(list(languages_found)),
            "programming_languages": sorted(list(prog_languages_found)),
            "coding_languages": sorted(list(prog_languages_found)),
            "social_links": social_links,
            "linkedin_url": social_links.get("linkedin"),
            "github_url": social_links.get("github"),
            "leetcode_url": social_links.get("leetcode"),
            "hackerrank_url": social_links.get("hackerrank"),
            "codeforces_url": social_links.get("codeforces"),
            "kaggle_url": social_links.get("kaggle"),
            "geeksforgeeks_url": social_links.get("geeksforgeeks"),
            "twitter_url": social_links.get("twitter"),
            "portfolio_url": social_links.get("portfolio"),
        }
        logger.debug("ResumeParser → name=%s, skills=%d, coding=%d, deployment=%d, internships=%d, links=%d",
                     name, len(result['skills']), len(result['coding_languages']), len(result['deployment_skills']), result['internship_count'], len(result['social_links']))
        return result


class TenthMarksheetParser(BaseParser):
    @classmethod
    def parse(cls, text: str, profile_name: Optional[str] = None) -> Dict[str, Any]:
        text = _normalize_ocr_text(text)
        lines = [line.strip() for line in text.split("\n") if line.strip()]
        text_lower = text.lower()

        name = cls.extract_name_from_lines(lines, profile_name=profile_name)

        board = fuzzy_match_institution(text, KNOWN_BOARDS) or "State Board of Secondary Education"

        passing_year = None
        ym = PASSING_YEAR_REGEX.search(text)
        if ym:
            try:
                passing_year = int(ym.group(1))
            except Exception:
                pass

        # 1. Subject-Wise Marks Table Extraction & Mathematical Percentage Calculation
        table_result = MarksTableExtractor.extract(text, exam_type="10th")
        percentage = None
        if table_result.get("total_subjects", 0) >= 3 and table_result.get("percentage", 0) > 0:
            percentage = table_result["percentage"]

        if percentage is None:
            pm = PERCENTAGE_REGEX.search(text)
            if pm:
                try:
                    val = float(pm.group(1))
                    if 0.0 <= val <= 100.0:
                        percentage = round(val, 2)
                except Exception:
                    pass

        if percentage is None:
            rpm = RAW_PERCENTAGE_REGEX.search(text)
            if rpm:
                try:
                    val = float(rpm.group(1))
                    if 0.0 <= val <= 100.0:
                        percentage = round(val, 2)
                except Exception:
                    pass

        # Calculate percentage from marks obtained & total marks
        if percentage is None:
            marks_match = re.search(r'(?:total|grand\s*total|marks\s*obtained)\s*[:=]?\s*([0-9]{2,3})\s*(?:/|out\s*of)\s*([0-9]{3})', text, re.IGNORECASE)
            if marks_match:
                try:
                    obtained = float(marks_match.group(1))
                    maximum = float(marks_match.group(2))
                    if 0 < obtained <= maximum and maximum in (500, 600, 700, 800, 1000):
                        percentage = round((obtained / maximum) * 100.0, 2)
                except Exception:
                    pass

        if percentage is None:
            # Pattern B: Number right before or after Grand Total of Marks Obtained
            gt_match = re.search(r'(?:grand\s*total|total\s*marks|marks\s*obtained|total\s*of\s*marks)[^\d\n]{0,30}(\d{2,3})', text, re.IGNORECASE)
            if not gt_match:
                gt_match = re.search(r'(\d{2,3})\s*\n[^\n]{0,30}(?:grand\s*total|total\s*marks|marks\s*obtained)', text, re.IGNORECASE)
            if gt_match:
                try:
                    total_val = float(gt_match.group(1))
                    if 200 <= total_val <= 600:
                        max_marks = 600.0 if total_val > 500 or (total_val / 600.0 > 0.5) else 500.0
                        percentage = round((total_val / max_marks) * 100.0, 2)
                except Exception:
                    pass

        if percentage is None:
            # Pattern C: Percentile Rank (PR)
            pr_match = re.search(r'(?:percentile\s*rank|percentile|pr)\s*[:=]?\s*([0-9]{2}(?:\.[0-9]+)?)', text, re.IGNORECASE)
            if pr_match:
                try:
                    percentage = round(float(pr_match.group(1)), 2)
                except Exception:
                    pass

        if percentage is None:
            # Pattern D: Mobile OCR / WhatsApp Screenshot line break layout
            ml_match = re.search(r'(?:percentage|percentile|percentile\s*rank|pr|marks|total)[^\d\n]*\n\s*([1-9][0-9](?:\.[0-9]{1,2})?)', text, re.IGNORECASE)
            if ml_match:
                try:
                    val = float(ml_match.group(1))
                    if 33.0 <= val <= 100.0:
                        percentage = round(val, 2)
                except Exception:
                    pass

        if percentage is None:
            # Pattern E: General valid decimal percentage token in document
            gen_match = re.search(r'\b([4-9][0-9]\.[0-9]{1,2})\b', text)
            if gen_match:
                try:
                    val = float(gen_match.group(1))
                    if 35.0 <= val <= 99.9:
                        percentage = round(val, 2)
                except Exception:
                    pass

        tenth_cgpa = None
        cgpa_match = CGPA_REGEX.search(text)
        if cgpa_match:
            try:
                c_val = float(cgpa_match.group(1))
                if 0.0 < c_val <= 10.0:
                    tenth_cgpa = round(c_val, 2)
                    if percentage is None:
                        percentage = round(c_val * 9.5, 2)
            except Exception:
                pass

        result = {
            "student_name": name,
            "board": board,
            "passing_year": passing_year,
            "tenth_percentage": percentage,
            "tenth_cgpa": tenth_cgpa,
            "marks_breakdown": table_result if table_result.get("total_subjects", 0) > 0 else None,
            "total_subjects": table_result.get("total_subjects"),
            "subjects": table_result.get("subjects"),
            "total_marks": table_result.get("total_marks_display"),
            "marks_report": table_result.get("formatted_report"),
        }
        if percentage is not None:
            logger.debug("TenthMarksheetParser: Successfully extracted percentage=%s, board=%s", percentage, board)
        else:
            logger.warning("TenthMarksheetParser: All percentage extraction strategies returned None for text sample")
        return result


class TwelfthDiplomaParser(BaseParser):
    @classmethod
    def parse(cls, text: str, profile_name: Optional[str] = None) -> Dict[str, Any]:
        text = _normalize_ocr_text(text)
        lines = [line.strip() for line in text.split("\n") if line.strip()]
        text_lower = text.lower()

        is_diploma = any(k in text_lower for k in ["diploma", "polytechnic", "technical examination", "gtu diploma"])
        doc_subtype = "DIPLOMA_MARKSHEET" if is_diploma else "TWELFTH_MARKSHEET"

        name = cls.extract_name_from_lines(lines, profile_name=profile_name)

        board = "Higher Secondary Education Board" if not is_diploma else "State Board of Technical Education"
        for code, full_name in KNOWN_BOARDS:
            if code.lower() in text_lower or full_name.lower() in text_lower:
                board = full_name
                break
        if is_diploma and ("baroda" in text_lower or "itm" in text_lower):
            board = "ITM SLS Baroda University"

        passing_year = None
        ym = PASSING_YEAR_REGEX.search(text)
        if ym:
            try:
                passing_year = int(ym.group(1))
            except Exception:
                pass
        if not passing_year:
            m_year = re.search(
                r'Two\s*Thousand\s*(Thirty|Twenty\s*(?:Nine|Eight|Seven|Six|Five|Four|Three|Two|One|Zero)?|Nineteen|Eighteen)',
                text, re.IGNORECASE
            )
            if m_year:
                words_map = {
                    "thirty": 2030,
                    "twenty nine": 2029, "twenty eight": 2028, "twenty seven": 2027,
                    "twenty six": 2026, "twenty five": 2025, "twenty four": 2024,
                    "twenty three": 2023, "twenty two": 2022, "twenty one": 2021,
                    "twenty": 2020, "nineteen": 2019, "eighteen": 2018,
                }
                passing_year = words_map.get(m_year.group(1).lower().strip())

        percentage = None
        cgpa = None
        table_result = None

        if not is_diploma:
            # 1. Subject-Wise Marks Table Extraction & Mathematical Percentage Calculation
            table_result = MarksTableExtractor.extract(text, exam_type="12th")
            if table_result.get("total_subjects", 0) >= 3 and table_result.get("percentage", 0) > 0:
                percentage = table_result["percentage"]

            if percentage is None:
                pm = PERCENTAGE_REGEX.search(text)
                if pm:
                    try:
                        val = float(pm.group(1))
                        if 0.0 <= val <= 100.0:
                            percentage = round(val, 2)
                    except Exception:
                        pass
            if percentage is None:
                rpm = RAW_PERCENTAGE_REGEX.search(text)
                if rpm:
                    try:
                        val = float(rpm.group(1))
                        if 0.0 <= val <= 100.0:
                            percentage = round(val, 2)
                    except Exception:
                        pass
        else:
            cm = CGPA_REGEX.search(text)
            if cm:
                try:
                    val = float(cm.group(1))
                    if 0.0 <= val <= 10.0:
                        cgpa = round(val, 2)
                except Exception:
                    pass
            pm = PERCENTAGE_REGEX.search(text)
            if pm:
                try:
                    val = float(pm.group(1))
                    if 0.0 <= val <= 100.0:
                        percentage = round(val, 2)
                except Exception:
                    pass

        result = {
            "document_subtype": doc_subtype,
            "student_name": name,
            "board_or_university": board,
            "passing_year": passing_year,
            "percentage": percentage,
            "diploma_cgpa": cgpa,
            "marks_breakdown": table_result if table_result and table_result.get("total_subjects", 0) > 0 else None,
            "total_subjects": table_result.get("total_subjects") if table_result else None,
            "subjects": table_result.get("subjects") if table_result else None,
            "total_marks": table_result.get("total_marks_display") if table_result else None,
            "marks_report": table_result.get("formatted_report") if table_result else None,
        }
        logger.debug("TwelfthDiplomaParser → subtype=%s, name=%s, pct=%s, cgpa=%s", doc_subtype, name, percentage, cgpa)
        return result


class UGMarksheetParser(BaseParser):
    @classmethod
    def parse(cls, text: str, profile_name: Optional[str] = None) -> Dict[str, Any]:
        text = _normalize_ocr_text(text)
        lines = [line.strip() for line in text.split("\n") if line.strip()]
        text_lower = text.lower()

        name = cls.extract_name_from_lines(lines, profile_name=profile_name)

        # University detection (fuzzy table-driven)
        university = fuzzy_match_institution(text, UNIVERSITY_MAP) or "University / Technical Institute"

        enrollment_no = None
        em = ENROLLMENT_REGEX.search(text)
        if em:
            enrollment_no = em.group(1).strip().upper()

        # Course detection (table-driven, no false default)
        course = None
        for keyword, course_name in COURSE_MAP:
            if keyword in text_lower:
                course = course_name
                break

        # Branch detection (table-driven, specific keywords)
        branch = None
        for keyword, branch_name in BRANCH_MAP:
            if keyword in text_lower:
                branch = branch_name
                break

        semester = None
        sm = re.search(r'(?:semester|sem)\s*[:\-]?\s*([1-8]|i{1,3}|iv|v|vi{1,2}|viii)\b', text, re.IGNORECASE)
        if sm:
            sem_raw = sm.group(1).upper()
            roman_map = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7, "VIII": 8}
            semester = roman_map.get(sem_raw) or (int(sem_raw) if sem_raw.isdigit() else None)

        sgpa = None
        cgpa = None

        # 1. Multi-column table layout: SGPA/SPI header followed by CGPA/CPI header, then values
        table_vert_sgpa_cgpa = re.search(
            r'\b(?:SGPA|SPI)\b[^\w\d\n]*\n\s*\b(?:CGPA|CPI)\b[^\d\n]*\n\s*([0-9]\.[0-9]{1,2})[^\d\n]*\n\s*([0-9]\.[0-9]{1,2})',
            text,
            re.IGNORECASE
        )
        if table_vert_sgpa_cgpa:
            try:
                val_sgpa = float(table_vert_sgpa_cgpa.group(1))
                val_cgpa = float(table_vert_sgpa_cgpa.group(2))
                if 0.0 <= val_sgpa <= 10.0:
                    sgpa = round(val_sgpa, 2)
                if 0.0 <= val_cgpa <= 10.0:
                    cgpa = round(val_cgpa, 2)
            except Exception:
                pass

        # 2. Multi-column table layout: CGPA/CPI header followed by SGPA/SPI header, then values
        if sgpa is None and cgpa is None:
            table_vert_cgpa_sgpa = re.search(
                r'\b(?:CGPA|CPI)\b[^\w\d\n]*\n\s*\b(?:SGPA|SPI)\b[^\d\n]*\n\s*([0-9]\.[0-9]{1,2})[^\d\n]*\n\s*([0-9]\.[0-9]{1,2})',
                text,
                re.IGNORECASE
            )
            if table_vert_cgpa_sgpa:
                try:
                    val_cgpa = float(table_vert_cgpa_sgpa.group(1))
                    val_sgpa = float(table_vert_cgpa_sgpa.group(2))
                    if 0.0 <= val_cgpa <= 10.0:
                        cgpa = round(val_cgpa, 2)
                    if 0.0 <= val_sgpa <= 10.0:
                        sgpa = round(val_sgpa, 2)
                except Exception:
                    pass

        # 3. Horizontal row table layout: SGPA/SPI and CGPA/CPI in the same line or row
        if sgpa is None and cgpa is None:
            table_horiz = re.search(
                r'\b(?:SGPA|SPI)\b[^\S\r\n]+\b(?:CGPA|CPI)\b[^\d\n]*\n[^\d\n]*([0-9]\.[0-9]{1,2})[^\S\r\n]+([0-9]\.[0-9]{1,2})',
                text,
                re.IGNORECASE
            )
            if table_horiz:
                try:
                    val_sgpa = float(table_horiz.group(1))
                    val_cgpa = float(table_horiz.group(2))
                    if 0.0 <= val_sgpa <= 10.0:
                        sgpa = round(val_sgpa, 2)
                    if 0.0 <= val_cgpa <= 10.0:
                        cgpa = round(val_cgpa, 2)
                except Exception:
                    pass

        # 4. Horizontal row with intermediate columns or loose spacing
        if cgpa is None and sgpa is None:
            lines = [l.strip() for l in text.split('\n') if l.strip()]
            for i, line in enumerate(lines):
                line_lower = line.lower()
                if ('sgpa' in line_lower or 'spi' in line_lower) and ('cgpa' in line_lower or 'cpi' in line_lower):
                    for k in range(i + 1, min(len(lines), i + 4)):
                        nums = re.findall(r'\b([0-9]\.[0-9]{1,2})\b', lines[k])
                        if len(nums) >= 2:
                            s_idx = min([idx for idx in [line_lower.find('sgpa'), line_lower.find('spi')] if idx >= 0] or [999])
                            c_idx = min([idx for idx in [line_lower.find('cgpa'), line_lower.find('cpi')] if idx >= 0] or [999])
                            val1, val2 = float(nums[0]), float(nums[1])
                            if s_idx < c_idx:
                                sgpa, cgpa = round(val1, 2), round(val2, 2)
                            else:
                                cgpa, sgpa = round(val1, 2), round(val2, 2)
                            break
                    if sgpa is not None or cgpa is not None:
                        break

        # 5. Standard labeled single-metric fallback
        if sgpa is None:
            sgpa_m = SGPA_REGEX.search(text)
            if sgpa_m:
                try:
                    val = float(sgpa_m.group(1))
                    if 0.0 <= val <= 10.0:
                        sgpa = round(val, 2)
                except Exception:
                    pass

        if cgpa is None:
            cgpa_m = CGPA_REGEX.search(text)
            if cgpa_m:
                try:
                    val = float(cgpa_m.group(1))
                    if 0.0 <= val <= 10.0:
                        cgpa = round(val, 2)
                except Exception:
                    pass

        # Always ensure CGPA is populated: if only SGPA or CPI is present, set CGPA
        if cgpa is None and sgpa is not None:
            cgpa = sgpa
        elif sgpa is None and cgpa is not None:
            sgpa = cgpa

        active_backlogs = None
        for pattern, fixed_val in BACKLOG_PATTERNS:
            bm = pattern.search(text)
            if bm:
                if fixed_val is not None:
                    active_backlogs = fixed_val
                else:
                    try:
                        active_backlogs = int(bm.group(1))
                    except Exception:
                        active_backlogs = None
                break

        backlog_result = active_backlogs if active_backlogs is not None else "UNKNOWN"

        result = {
            "student_name": name,
            "university": university,
            "enrollment_number": enrollment_no,
            "course": course,
            "branch": branch,
            "current_semester": semester,
            "sgpa": sgpa,
            "cgpa": cgpa,
            "active_backlogs": backlog_result,
        }
        if sgpa is None:
            logger.warning("UGMarksheetParser: SGPA extraction yielded None across all table and regex strategies.")
        if cgpa is None:
            logger.warning("UGMarksheetParser: CGPA extraction yielded None across all table and regex strategies.")
        logger.debug("UGMarksheetParser → name=%s, sgpa=%s, cgpa=%s, backlogs=%s, course=%s, branch=%s",
                     name, sgpa, cgpa, backlog_result, course, branch)
        return result