"""
Gemini Multimodal AI Document Extractor.
Uses Google Gemini Flash vision to accurately parse Indian academic marksheets (10th, 12th, UG)
directly from document bytes or OCR text.
"""
import io
import os
import json
import logging
from typing import Optional, Dict, Any
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger("talentloq.gemini_extractor")

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")

try:
    from google import genai
    from google.genai import types
    _genai_available = True
except ImportError:
    genai = None
    types = None
    _genai_available = False


class GeminiDocumentExtractor:
    @classmethod
    def get_client(cls) -> Optional[Any]:
        if not _genai_available or not GEMINI_API_KEY:
            return None
        try:
            return genai.Client(api_key=GEMINI_API_KEY)
        except Exception as e:
            logger.warning("Failed to initialize Gemini Client: %s", e)
            return None

    @classmethod
    def extract_resume(cls, file_bytes: Optional[bytes] = None, filename: str = "", ocr_text: str = "") -> Optional[Dict[str, Any]]:
        """
        1st : Resume : Skills, Coding language, Spoken language, URIs of linkedin, github, leetcode, hackerrank, codeforces, kaggle, geeksforgeeks and twitter.
        """
        client = cls.get_client()
        if not client:
            return None

        prompt = """You are an expert technical resume parser.
Analyze this resume document and extract:
1. skills: Array of technical skills, tools, frameworks, databases, libraries, and methodologies (e.g. Docker, Flutter, MongoDB, React, Node.js, FastAPI, Git, CI/CD, AWS).
2. coding_languages: Array of programming languages (e.g. Python, Java, C++, C, JavaScript, TypeScript, Dart, Go, Rust, Kotlin, Swift, SQL, HTML, CSS).
3. deployment_skills: Array of cloud, DevOps, container, and hosting skills (e.g. Docker, Kubernetes, AWS, GCP, Azure, CI/CD, GitHub Actions, Jenkins, Nginx, Linux, Vercel, Netlify).
4. internships: Array of professional internships or work experiences. Each object must have:
   - company_name: Name of company/organization
   - role_title: Job role / title (e.g. Software Engineer Intern, Web Developer Intern)
   - duration: Time period or dates (e.g. 'Jun 2024 - Aug 2024' or '3 Months')
   - description: Summary of responsibilities and tech stack
5. internship_count: Total integer count of internships / work experiences found (0 if none).
6. spoken_languages: Array of natural / spoken human languages (e.g. English, Hindi, Gujarati, French, German, Spanish, etc. If not explicitly listed, extract any mentioned or infer default ['English']).
7. URIs / URLs for candidate profiles (extract full valid URLs or null if not found):
   - linkedin: LinkedIn profile URI
   - github: GitHub profile URI
   - leetcode: LeetCode profile URI
   - hackerrank: HackerRank profile URI
   - codeforces: Codeforces profile URI
   - kaggle: Kaggle profile URI
   - geeksforgeeks: GeeksforGeeks profile URI
   - twitter: Twitter or X profile URI

Return strictly valid JSON with this exact structure:
{
  "skills": ["Flutter", "FastAPI", "MongoDB", "Docker", "React"],
  "coding_languages": ["Python", "JavaScript", "Dart", "C++", "SQL"],
  "deployment_skills": ["Docker", "AWS", "CI/CD", "Linux"],
  "internships": [
    {
      "company_name": "Acme Tech Solutions",
      "role_title": "Backend Engineering Intern",
      "duration": "May 2024 - Jul 2024",
      "description": "Developed REST APIs with FastAPI and Docker containerization."
    }
  ],
  "internship_count": 1,
  "spoken_languages": ["English", "Hindi", "Gujarati"],
  "uris": {
    "linkedin": "https://linkedin.com/in/...",
    "github": "https://github.com/...",
    "leetcode": null,
    "hackerrank": null,
    "codeforces": null,
    "kaggle": null,
    "geeksforgeeks": null,
    "twitter": null
  }
}
"""
        return cls._call_gemini_with_fallback(client, prompt, file_bytes, filename, ocr_text)

    @classmethod
    def extract_tenth_marksheet(cls, file_bytes: Optional[bytes] = None, filename: str = "", ocr_text: str = "") -> Optional[Dict[str, Any]]:
        """
        2nd : 10th marksheet : percentage, if 5 subjects are mentioned calculate their total from 500 and if 6 subjects are mentioned calculate their total from 600.
        """
        client = cls.get_client()
        if not client:
            return None

        prompt = """You are an expert academic marksheet parser for Indian education boards (CBSE, GSEB, ICSE, State Boards).
Carefully inspect this 10th examination marksheet.
CRITICAL RULES FOR CALCULATION:
- If a Grand Total, Total Marks, or Board Percentage is explicitly printed on the marksheet (e.g. 'Total: 464', 'Percentage: 92.8%', 'Grand Total: 480/500'), prioritize and extract that official printed total / percentage directly!
- If calculating manually:
  - Count the valid core academic subjects.
  - Exclude co-scholastic / non-academic subjects (such as Work Experience, Health & Physical Education, Environmental Studies, Yoga, School-based computer grades).
  - If 5 subjects are mentioned or board uses Best-of-5: calculate their total out of 500: percentage = (total_marks_obtained / 500) * 100.
  - If 6 subjects are mentioned and all count toward result: calculate their total out of 600: percentage = (total_marks_obtained / 600) * 100.
  - If a subject has a maximum score other than 100, normalize it out of 100 first.
  - If a Grand Total is explicitly printed (e.g. Total: 464), use it as total_marks_obtained.

Return strictly valid JSON with this exact structure:
{
  "student_name": "...",
  "board": "...",
  "passing_year": 2021,
  "exam": "10th",
  "total_subjects": 6,
  "subjects": [
    {"subject_name": "Gujarati", "marks_obtained": 85.0, "max_marks": 100.0}
  ],
  "total_marks_obtained": 464.0,
  "total_max_marks": 600.0,
  "percentage": 77.33
}
"""
        return cls._call_gemini_with_fallback(client, prompt, file_bytes, filename, ocr_text)

    @classmethod
    def extract_twelfth_or_diploma(cls, file_bytes: Optional[bytes] = None, filename: str = "", ocr_text: str = "") -> Optional[Dict[str, Any]]:
        """
        3rd : 12th or diploma : percentage, if 5 subjects are mentioned calculate their total from 500 and if 6 subjects are mentioned calculate their total from 600 or if diploma is present then fetch CGPA.
        """
        client = cls.get_client()
        if not client:
            return None

        prompt = """You are an expert academic marksheet parser for Indian Higher Secondary Boards (Class 12th) and Technical Diploma Examinations.
Inspect this document and determine whether it is a Class 12th Marksheet or a Diploma Marksheet:

CASE A: If it is a 12th Marksheet:
- Count valid academic subjects (excluding non-academic subjects).
- If 5 subjects are mentioned: calculate their total out of 500: percentage = (total_marks_obtained / 500) * 100.
- If 6 subjects are mentioned: calculate their total out of 600: percentage = (total_marks_obtained / 600) * 100.
- Return document_subtype = "TWELFTH_MARKSHEET".

CASE B: If it is a Diploma Marksheet:
- Fetch the CGPA (or CPI / Cumulative Grade Point Average).
- If only SPI / SGPA is given, use it as CGPA.
- Return document_subtype = "DIPLOMA_MARKSHEET".

Return strictly valid JSON:
{
  "document_subtype": "TWELFTH_MARKSHEET" or "DIPLOMA_MARKSHEET",
  "student_name": "...",
  "board_or_college": "...",
  "passing_year": 2023,
  "percentage": 84.0,
  "total_subjects": 5,
  "total_marks_obtained": 420.0,
  "total_max_marks": 500.0,
  "diploma_cgpa": null,
  "subjects": [
    {"subject_name": "Physics", "marks_obtained": 85.0, "max_marks": 100.0}
  ]
}
OR for Diploma:
{
  "document_subtype": "DIPLOMA_MARKSHEET",
  "student_name": "...",
  "board_or_college": "...",
  "passing_year": 2023,
  "diploma_cgpa": 8.42,
  "percentage": null,
  "total_subjects": null,
  "total_marks_obtained": null,
  "total_max_marks": null,
  "subjects": []
}
"""
        return cls._call_gemini_with_fallback(client, prompt, file_bytes, filename, ocr_text)

    @classmethod
    def extract_ug_marksheet(cls, file_bytes: Optional[bytes] = None, filename: str = "", ocr_text: str = "") -> Optional[Dict[str, Any]]:
        """
        4th : undergraduate result : fetch current backlogs, total CGPA, Enrollment no.
        """
        client = cls.get_client()
        if not client:
            return None

        prompt = """You are an expert university grade card analyzer for Indian universities.
Inspect this Undergraduate (UG) degree marksheet / semester grade report.
Extract:
1. current_backlogs: Active / current backlogs count (integer). If all subjects cleared or passed, set to 0.
2. total_cgpa: Total / Cumulative CGPA (or CPI) out of 10.0. If only SGPA / SPI is present, use it here.
3. enrollment_no: Candidate enrollment number / Roll number / Registration number.
4. sgpa: Semester GPA / SPI (float).
5. student_name: Candidate full name.
6. university: University name.
7. course: Degree course (e.g. B.Tech).
8. branch: Branch specialization (e.g. Computer Science & Engineering).
9. current_semester: Semester number (integer, e.g. 6).

Return strictly valid JSON with this exact structure:
{
  "student_name": "...",
  "university": "...",
  "enrollment_no": "...",
  "course": "B.Tech",
  "branch": "Computer Science & Engineering",
  "current_semester": 6,
  "current_backlogs": 0,
  "total_cgpa": 7.41,
  "sgpa": 7.41
}
"""
        return cls._call_gemini_with_fallback(client, prompt, file_bytes, filename, ocr_text)

    @classmethod
    def _call_gemini_with_fallback(
        cls,
        client: Any,
        prompt: str,
        file_bytes: Optional[bytes],
        filename: str,
        ocr_text: str
    ) -> Optional[Dict[str, Any]]:
        # Candidate models prioritized by stability, response speed, and generous quota
        candidate_models = [
            "gemini-3.5-flash-lite",
            "gemini-3.5-flash",
            "gemini-flash-lite-latest",
            "gemini-3.6-flash",
            "gemini-flash-latest",
        ]

        contents = []
        mime_type = "application/pdf"
        fn_lower = filename.lower()
        if fn_lower.endswith(".png"):
            mime_type = "image/png"
        elif fn_lower.endswith((".jpg", ".jpeg")):
            mime_type = "image/jpeg"

        if file_bytes and types:
            safe_bytes = file_bytes
            # Downscale images above 1280px to optimize vision tile tokens and stay well within inline limits
            if mime_type.startswith("image/"):
                try:
                    from PIL import Image
                    img = Image.open(io.BytesIO(file_bytes))
                    if max(img.size) > 1280:
                        img.thumbnail((1280, 1280), Image.Resampling.LANCZOS)
                        buf = io.BytesIO()
                        img.convert("RGB").save(buf, format="JPEG", quality=82, optimize=True)
                        safe_bytes = buf.getvalue()
                        mime_type = "image/jpeg"
                        logger.debug("Optimized image dimensions to <= 1280px for Gemini vision token efficiency")
                except Exception as e:
                    logger.warning("Could not optimize image size: %s", e)
            elif mime_type == "application/pdf" and len(file_bytes) > 10 * 1024 * 1024:
                try:
                    import fitz
                    doc = fitz.open(stream=file_bytes, filetype="pdf")
                    if len(doc) > 0:
                        pix = doc[0].get_pixmap(dpi=150)
                        safe_bytes = pix.tobytes("jpeg")
                        mime_type = "image/jpeg"
                        logger.info("Rendered page 1 of oversized PDF (%.1f MB) to JPEG (%.2f MB) for Gemini", len(file_bytes)/(1024*1024), len(safe_bytes)/(1024*1024))
                except Exception as e:
                    logger.warning("Could not render page from large PDF: %s", e)

        # Payload de-duplication:
        # If dense, high-confidence native text was already extracted (e.g. from digital text PDF),
        # sending ONLY the text skips expensive multimodal vision tile processing.
        # Otherwise, send the downscaled visual byte part + concise supplemental text.
        has_dense_native_text = bool(ocr_text and len(ocr_text.strip()) > 350 and not mime_type.startswith("image/"))
        if has_dense_native_text:
            contents.append(f"Document Text:\n{ocr_text[:3000]}\n\n{prompt}")
        else:
            if safe_bytes and types:
                try:
                    contents.append(types.Part.from_bytes(data=safe_bytes, mime_type=mime_type))
                except Exception as e:
                    logger.debug("Failed to create byte part: %s", e)
            if ocr_text:
                contents.append(f"Supplemental OCR text:\n{ocr_text[:500]}")
            contents.append(prompt)

        for model_name in candidate_models:
            for attempt in range(2):
                try:
                    logger.info("Attempting Gemini document extraction with model=%s (attempt %d)", model_name, attempt + 1)
                    config = types.GenerateContentConfig(response_mime_type="application/json") if types else {}
                    response = client.models.generate_content(
                        model=model_name,
                        contents=contents,
                        config=config
                    )

                    usage = getattr(response, "usage_metadata", None)
                    p_tok = int(getattr(usage, "prompt_token_count", 0) or 0)
                    c_tok = int(getattr(usage, "candidates_token_count", 0) or 0)
                    t_tok = int(getattr(usage, "total_token_count", 0) or (p_tok + c_tok))

                    print(
                        f"\n\033[1;36m+==================== [AI API TOKEN USAGE] ====================+\033[0m\n"
                        f"  \033[1mTask:\033[0m              Multimodal Document OCR & Extraction\n"
                        f"  \033[1mProvider:\033[0m          GOOGLE GEMINI\n"
                        f"  \033[1mModel:\033[0m             {model_name}\n"
                        f"  \033[1;33mPrompt Tokens:\033[0m     {p_tok:,}\n"
                        f"  \033[1;32mCompletion Tokens:\033[0m {c_tok:,}\n"
                        f"  \033[1;35mTotal Tokens Used:\033[0m {t_tok:,}\n"
                        f"\033[1;36m+==============================================================+\033[0m\n",
                        flush=True
                    )
                    logger.info(
                        "[AI Token Usage] Gemini Document Extraction | Model: %s | Prompt: %d | Completion: %d | Total: %d",
                        model_name, p_tok, c_tok, t_tok
                    )

                    raw_text = response.text.strip()
                    # Strip possible markdown code fence
                    if raw_text.startswith("```json"):
                        raw_text = raw_text[7:]
                    if raw_text.startswith("```"):
                        raw_text = raw_text[3:]
                    if raw_text.endswith("```"):
                        raw_text = raw_text[:-3]

                    parsed = json.loads(raw_text.strip())
                    logger.info("Gemini document extraction succeeded via model=%s", model_name)
                    return parsed
                except Exception as err:
                    err_str = str(err)
                    # If 429 quota exhausted or 503 unavailable, failover immediately to next model
                    if "429" in err_str or "RESOURCE_EXHAUSTED" in err_str or "503" in err_str or "UNAVAILABLE" in err_str:
                        logger.warning("Gemini model=%s hit quota/capacity limit (failing over): %s", model_name, err_str[:120])
                        break
        # Mistral fallback if all Gemini models failed or were exhausted
        mistral_key = os.getenv("MISTRAL_API_KEY", "").strip()
        if mistral_key and ocr_text:
            try:
                import httpx
                resp = httpx.post(
                    "https://api.mistral.ai/v1/chat/completions",
                    headers={"Authorization": f"Bearer {mistral_key}", "Content-Type": "application/json"},
                    json={
                        "model": "mistral-small-latest",
                        "messages": [{"role": "user", "content": f"{prompt}\n\nDocument Text:\n{ocr_text[:3000]}"}],
                        "response_format": {"type": "json_object"},
                    },
                    timeout=12.0
                )
                if resp.status_code == 200:
                    raw = resp.json()["choices"][0]["message"]["content"]
                    logger.info("Mistral fallback document extraction succeeded via mistral-small-latest")
                    return json.loads(raw)
            except Exception as e:
                logger.warning("Mistral fallback document extraction failed: %s", e)

        return None
