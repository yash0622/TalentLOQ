"""
Local Resume ATS Doctor & Keyword Gap Analyzer for TalentLOQ.
100% offline, deterministic, sub-millisecond execution. Zero external API cost.
Analyzes:
1. Keyword & Skill Overlap (exact match + canonical equivalence)
2. Bullet Quality & Action Verbs at line starts
3. Quantifiable Impact Metrics (strict unit-bearing regex, zero bare-number false positives)
4. Structural Format Health & Parseability (standard headers, contact info, multi-column risks)
"""
from typing import Dict, Any, List, Optional
import re
from app.services.skill_matcher import skill_matcher_engine

# Curated high-impact technical action verbs commonly scored by ATS engines
STRONG_ACTION_VERBS = {
    "architected", "built", "created", "designed", "developed", "deployed",
    "engineered", "implemented", "integrated", "optimized", "orchestrated",
    "refactored", "scaled", "streamlined", "automated", "migrated", "reduced",
    "accelerated", "configured", "debugged", "maintained", "trained", "led",
    "spearheaded", "executed", "established", "formulated", "published"
}

# Standard section header regex patterns expected by enterprise ATS parsers
SECTION_PATTERNS = {
    # Requires explicit 'academics' or 'academic background/history/qualifications' so 'Academic Projects' does NOT falsely match Education
    "Education": re.compile(r'^\s*(?:#+\s*)?(?:educations?|academics|academic\s+(?:background|history|credentials|qualifications|record)|qualifications)\b', re.IGNORECASE | re.MULTILINE),
    "Skills": re.compile(r'^\s*(?:#+\s*)?(?:skills|technical\s+skills|core\s+competencies|technologies|proficiencies)\b', re.IGNORECASE | re.MULTILINE),
    "Experience": re.compile(r'^\s*(?:#+\s*)?(?:experience|work\s+experience|employment|internships?|professional\s+experience)\b', re.IGNORECASE | re.MULTILINE),
    "Projects": re.compile(r'^\s*(?:#+\s*)?(?:projects|technical\s+projects|academic\s+projects|key\s+projects)\b', re.IGNORECASE | re.MULTILINE),
}

# Strict unit/symbol-bearing impact metrics regex.
# Eliminates false positives from bare graduation years (2024, 2026), phone numbers, or CGPA 10,
# while supporting %, x, k, ms, s/sec/seconds, mb, gb, and +.
STRICT_METRICS_REGEX = re.compile(
    r'\b\d+(\.\d+)?\s*(%|x|k|ms|mb|gb|\+|sec|seconds?)\b|\b(?<!\d)(?:\d{1,3}(?:\.\d+)?)\s*s\b',
    re.IGNORECASE
)

# Pattern recognizing right-aligned dates, years, and durations in resume headers/entries
RIGHT_ALIGNED_DATE_REGEX = re.compile(
    r'(?:\b(?:19|20)\d{2}\b|\bpresent\b|\bcurrent\b|\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b)',
    re.IGNORECASE
)

# Bullet start detector (handles unicode bullet glyphs, dashes, asterisks, numbered lists, and optional markdown bold/emphasis)
BULLET_START_REGEX = re.compile(
    r'^\s*(?:[•\-\*\u2022\u2023\u25E6\u2043\u2219]|\d+[\.\)])\s*(?:\*{1,2}|_{1,2})?\s*([a-zA-Z]+)',
    re.MULTILINE
)
LINE_START_REGEX = re.compile(r'^\s*(?:\*{1,2}|_{1,2})?\s*([a-zA-Z]+)\b', re.MULTILINE)

EMAIL_REGEX = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b')
PHONE_REGEX = re.compile(r'(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}')


DATE_TOKENS = {
    "jan", "january", "feb", "february", "mar", "march", "apr", "april",
    "may", "jun", "june", "jul", "july", "aug", "august", "sep", "september",
    "oct", "october", "nov", "november", "dec", "december", "present", "current",
    "spring", "summer", "fall", "autumn", "winter"
}

def is_right_aligned_date_token(text: str) -> bool:
    clean = text.strip()
    words = re.findall(r'[a-zA-Z0-9]+', clean)
    if not words or len(words) > 5:
        return False
    date_word_count = sum(
        1 for w in words
        if w.lower() in DATE_TOKENS or (w.isdigit() and (len(w) == 4 or len(w) <= 2))
    )
    return date_word_count >= len(words) * 0.7


class ResumeAtsDoctor:
    @classmethod
    def check_format_health(cls, resume_text: str) -> Dict[str, Any]:
        """
        Evaluates document parseability, standard section presence,
        contact information visibility, and layout fragmentation risks.
        """
        text = resume_text or ""
        warnings: List[str] = []
        sections_found: List[str] = []

        # 1. Section Header Detection
        for sec_name, pattern in SECTION_PATTERNS.items():
            if pattern.search(text):
                sections_found.append(sec_name)
            else:
                warnings.append(f"Missing standard '{sec_name}' section header.")

        # 2. Contact Info Detection in Body Text
        has_email = bool(EMAIL_REGEX.search(text))
        has_phone = bool(PHONE_REGEX.search(text))
        if not has_email:
            warnings.append("No email address detected in body text (may be trapped in header/footer).")
        if not has_phone:
            warnings.append("No phone number detected in body text (may be trapped in header/footer).")

        # 3. Layout Risk (Multi-column / table fragmentation)
        # Lines with wide interior whitespace gaps between disparate body texts often indicate
        # multi-column table layouts that scramble ATS readers.
        # Right-aligned dates and durations (e.g. 'Software Engineer          Jun 2024 - Aug 2024')
        # are standard single-column lines and are exempted from layout risk.
        multi_column_lines = 0
        for line in text.splitlines():
            gaps = list(re.finditer(r'\s{5,}', line))
            if len(gaps) >= 2:
                # 3+ columns in a single line indicates a multi-column table
                multi_column_lines += 1
                continue
            elif len(gaps) == 1:
                left_part = line[:gaps[0].start()].strip()
                right_part = line[gaps[0].end():].strip()
                # Skip normal right-aligned dates, durations, or year intervals
                if is_right_aligned_date_token(right_part):
                    continue
                # If both sides contain substantive non-date textual columns
                if len(left_part) >= 3 and len(right_part) >= 3:
                    multi_column_lines += 1

        has_layout_risk = multi_column_lines >= 4
        if has_layout_risk:
            warnings.append("Multi-column layout or table structures detected — text may parse out-of-order.")

        # Compute format health score (0-100)
        # Sections: 4 * 15 = 60 pts
        # Contact info: 20 pts
        # Clean layout: 20 pts
        format_score = (len(sections_found) * 15)
        if has_email:
            format_score += 10
        if has_phone:
            format_score += 10
        if not has_layout_risk:
            format_score += 20

        return {
            "format_score": min(100, format_score),
            "sections_detected": sections_found,
            "has_contact_info": has_email and has_phone,
            "has_layout_risk": has_layout_risk,
            "format_warnings": warnings,
        }

    @classmethod
    def analyze_resume_fit(
        cls,
        resume_text: str,
        student_skills: List[str],
        projects: List[Any],
        drive_doc: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Comprehensive ATS analysis combining keyword overlap, bullet quality,
        strict impact metrics, and structural format health.
        """
        raw_text = resume_text or ""
        drive_desc = drive_doc.get("description", "")
        req_skills = drive_doc.get("extracted_required_skills") or []
        if not req_skills:
            manual_req = drive_doc.get("required_skills") or []
            extracted = skill_matcher_engine.extract_skills_from_text(drive_desc, use_ner=False)
            req_skills = sorted(list(set(manual_req + extracted)))
        if not req_skills:
            req_skills = ["Software Engineering", "Problem Solving"]

        # Extract skills present in resume text if student_skills is sparse
        extracted_from_resume = skill_matcher_engine.extract_skills_from_text(raw_text, use_ner=False)
        combined_candidate_skills = sorted(list(set((student_skills or []) + extracted_from_resume)))

        # 1. Skill & Keyword Overlap (exact + semantic equivalences)
        overlap = skill_matcher_engine.compute_skill_overlap(combined_candidate_skills, req_skills)
        matched_skills = overlap["matched_skills"]
        missing_skills = overlap["missing_skills"]
        overlap_ratio = overlap["overlap_ratio"]

        # 2. Bullet Action Verbs Audit (Evaluates verbs starting bullets or lines)
        bullet_start_verbs = set()
        # Glyphed bullets (•, -, *, etc.)
        for match in BULLET_START_REGEX.finditer(raw_text):
            word = match.group(1).lower()
            if word in STRONG_ACTION_VERBS:
                bullet_start_verbs.add(word)

        # Standard line starts in resume
        for match in LINE_START_REGEX.finditer(raw_text):
            word = match.group(1).lower()
            if word in STRONG_ACTION_VERBS:
                bullet_start_verbs.add(word)

        # Also inspect project description lines/bullets
        for p in (projects or []):
            desc = p.get("description", "") if isinstance(p, dict) else str(p)
            for match in LINE_START_REGEX.finditer(desc):
                word = match.group(1).lower()
                if word in STRONG_ACTION_VERBS:
                    bullet_start_verbs.add(word)

        # Also collect total action verbs in document
        all_words = set(re.findall(r'[a-zA-Z]+', raw_text.lower()))
        found_action_verbs = sorted(list(all_words & STRONG_ACTION_VERBS))

        # 3. Quantifiable Metrics Audit (STRICT unit/symbol-bearing regex)
        full_text = f"{raw_text} " + " ".join([
            f"{p.get('title', '')} {p.get('description', '')}" if isinstance(p, dict) else str(p)
            for p in (projects or [])
        ])
        metric_matches = STRICT_METRICS_REGEX.findall(full_text)
        has_metrics = len(metric_matches) > 0

        # 4. Structural Format Health Check
        format_health = cls.check_format_health(raw_text)

        # 5. Composite ATS Score Calculation (0-100)
        # - 50% Keyword & Skill Match (overlap_ratio * 50)
        # - 25% Bullet Impact & Metrics (up to 15 for bullet-start action verbs + 10 for metrics)
        # - 25% Structural Format Health (format_score * 0.25)
        skill_score = overlap_ratio * 50.0
        verb_score = min(15.0, len(bullet_start_verbs) * 5.0)
        metric_score = 10.0 if has_metrics else 0.0
        format_score = format_health["format_score"] * 0.25

        ats_score = int(round(min(100.0, skill_score + verb_score + metric_score + format_score)))

        # 6. Determine Fit Tier
        if ats_score >= 80:
            fit_tier = "EXCELLENT MATCH"
        elif ats_score >= 60:
            fit_tier = "STRONG MATCH"
        elif ats_score >= 40:
            fit_tier = "MODERATE MATCH"
        else:
            fit_tier = "NEEDS OPTIMIZATION"

        # 7. Actionable Suggestions (Prioritized)
        suggestions: List[str] = []
        if missing_skills:
            top_missing = missing_skills[:3]
            suggestions.append(f"Add missing keywords: {', '.join(top_missing)} to your skills or projects.")
        if not has_metrics:
            suggestions.append("Quantify your achievements with metrics (e.g., 'improved performance by 25%', 'handled 500+ users').")
        if len(bullet_start_verbs) < 2:
            suggestions.append("Start bullet points with strong action verbs like 'Built', 'Optimized', 'Deployed', or 'Architected'.")
        if format_health["format_warnings"]:
            suggestions.append(format_health["format_warnings"][0])
        if not suggestions:
            suggestions.append("Your resume aligns strongly with this job's automated screening filters.")

        return {
            "ats_score": ats_score,
            "fit_tier": fit_tier,
            "match_count": len(matched_skills),
            "total_required": len(req_skills),
            "matched_skills": matched_skills,
            "missing_skills": missing_skills,
            "semantic_equivalences": overlap.get("semantic_equivalences", []),
            "bullet_action_verbs": sorted(list(bullet_start_verbs))[:5],
            "found_action_verbs": found_action_verbs[:5],
            "has_quantifiable_metrics": has_metrics,
            "metric_count": len(metric_matches),
            "format_health": format_health,
            "suggestions": suggestions[:4],
        }

resume_ats_doctor = ResumeAtsDoctor()