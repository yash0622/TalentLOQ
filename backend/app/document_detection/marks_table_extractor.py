"""
10th & 12th Result Marks Extraction and Percentage Calculation System.

Scans uploaded 10th or 12th examination marksheet/result using OCR/native text,
detects the subject marks table, filters out non-academic or grade-only entries,
extracts individual subject scores, normalizes to 100 where required,
and calculates the mathematically accurate overall percentage.
"""
import re
import logging
from typing import Dict, Any, List, Optional, Tuple

logger = logging.getLogger(__name__)

# Core academic subjects recognized in 10th and 12th boards (CBSE, ICSE, State Boards)
CORE_ACADEMIC_KEYWORDS = [
    # Languages
    "english", "hindi", "gujarati", "sanskrit", "marathi", "punjabi", "urdu",
    "bengali", "tamil", "telugu", "kannada", "malayalam", "odia", "assamese",
    "french", "german", "spanish",
    # 10th Core
    "mathematics", "maths", "math", "science", "social science", "social studies",
    "sst", "general science", "basic mathematics", "standard mathematics",
    # 12th Sciences
    "physics", "chemistry", "biology", "biotechnology", "computer science",
    "informatics practices", "information technology", "applied mathematics",
    # 12th Commerce
    "accountancy", "accounts", "business studies", "economics", "commerce",
    "statistics", "entrepreneurship", "commercial studies",
    # 12th Arts / Humanities
    "history", "geography", "political science", "civics", "psychology",
    "sociology", "philosophy", "legal studies", "home science"
]

# Explicitly excluded non-academic, co-scholastic, or grade-only activities
EXCLUDED_KEYWORDS = [
    "work experience", "work education", "w.e.", "w e", "supw",
    "physical education", "health and physical education", "physical & health education",
    "physical & health", "health education", "p.e.", "sports", "yoga", "ncc",
    "general studies", "general knowledge", "gk", "g.s.",
    "discipline", "environmental education", "environmental studies", "evs",
    "art education", "drawing", "painting", "craft", "music", "dance",
    "moral science", "value education", "life skills", "internal assessment",
    "library", "social service", "cca", "attendance"
]

# Administrative lines to ignore when scanning for subject rows
ADMIN_KEYWORDS = [
    "roll no", "seat no", "mother's name", "father's name", "guardian's name",
    "candidate's name", "student's name", "school name", "centre", "center",
    "registration", "reg no", "date of birth", "dob", "result", "status",
    "division", "grand total", "total marks", "percentage", "percentile",
    "statement of marks", "secondary school", "higher secondary", "marksheet",
    "certificate", "board", "examination", "pariksha"
]


class MarksTableExtractor:
    """
    Extracts subject-wise marks and computes overall percentage for 10th / 12th results.
    """

    @classmethod
    def extract(cls, text: str, exam_type: str = "10th") -> Dict[str, Any]:
        """
        Main extraction entry point.
        
        Args:
            text: Normalized document text (from OCR or PDF).
            exam_type: '10th' or '12th'.
            
        Returns:
            Dict containing:
            - exam: '10th' or '12th'
            - total_subjects: int
            - subjects: List[Dict[str, Any]]
            - total_marks_obtained: float
            - total_max_marks: float
            - total_marks_display: str (e.g. '412/500')
            - percentage: float (e.g. 82.40)
            - formatted_report: str (formatted according to user prompt)
        """
        # Preprocess text for OCR quirks (split lines & internal spaces in subjects)
        norm_text = re.sub(r'(\bSOCIAL\b)\s*\n\s*(\bSC\s*IENCE\b)', r'\1 \2', text, flags=re.I)
        norm_text = re.sub(r'\bsc\s+ience\b', 'SCIENCE', norm_text, flags=re.I)
        norm_text = re.sub(r'\bengl\s+ish\b', 'ENGLISH', norm_text, flags=re.I)
        norm_text = re.sub(r'\bsans\s+krit\b', 'SANSKRIT', norm_text, flags=re.I)
        norm_text = re.sub(r'\bguj\s*ar\s*ati\b', 'GUJARATI', norm_text, flags=re.I)
        norm_text = re.sub(r'\bmath\s*em\s*atics\b', 'MATHEMATICS', norm_text, flags=re.I)
        norm_text = re.sub(r'\bsoc\s*ial\b', 'SOCIAL', norm_text, flags=re.I)

        lines = [line.strip() for line in norm_text.split("\n") if line.strip()]

        def _get_subject_key(sub_name: str) -> str:
            n_low = sub_name.lower()
            if "social" in n_low:
                return "social_science"
            if "science" in n_low:
                return "science"
            return n_low.split()[0]

        subjects: List[Dict[str, Any]] = []
        seen_subject_keys = set()

        for line in lines:
            line_clean = line.strip()
            line_lower = line_clean.lower()

            # 1. Skip non-academic / grade-only subjects
            if any(k in line_lower for k in EXCLUDED_KEYWORDS):
                continue

            # 2. Skip administrative header / footer lines
            if any(k in line_lower for k in ADMIN_KEYWORDS):
                continue

            # 3. Check if line contains a recognizable academic subject keyword
            matched_academic = None
            for kw in CORE_ACADEMIC_KEYWORDS:
                # Match whole word
                if re.search(r'\b' + re.escape(kw) + r'\b', line_lower):
                    matched_academic = kw
                    break

            if not matched_academic:
                continue

            # 4. Attempt to parse subject name and marks from this line
            parsed = cls._parse_subject_line(line_clean, matched_academic)
            if parsed:
                key = _get_subject_key(parsed["subject_name"])
                if key not in seen_subject_keys:
                    seen_subject_keys.add(key)
                    subjects.append(parsed)

        # If line-by-line caught fewer than 5 subjects, use multi-line table extraction
        if len(subjects) < 5:
            table_subjects = cls._extract_from_table_layout(lines)
            for sub in table_subjects:
                key = _get_subject_key(sub["subject_name"])
                if key not in seen_subject_keys:
                    seen_subject_keys.add(key)
                    subjects.append(sub)

        total_subjects = len(subjects)

        # Check if an explicit grand total is printed at the bottom of the marksheet
        # e.g. 'Total:\n464' or 'GRAND TOTAL OF MARKS OBTAINED 464'
        printed_grand_total = None
        gt_match = re.search(r'(?:grand\s*total[^\d\n]*|total\s*:?)\s*\n?\s*(\d{3})\b', norm_text, re.I)
        if gt_match:
            try:
                val = float(gt_match.group(1))
                if 200.0 <= val <= 700.0:
                    printed_grand_total = val
            except Exception:
                pass

        # Check if an explicit percentage is printed (e.g. 'Percentage: 73.17%' or '73.17%')
        printed_percentage = None
        pct_match = re.search(r'(?:percentage|percent|result[^\d\n]*)\s*[:=]?\s*(\d{2}(?:\.\d{1,2})?)\s*%', norm_text, re.I)
        if pct_match:
            try:
                pval = float(pct_match.group(1))
                if 25.0 <= pval <= 100.0:
                    printed_percentage = pval
            except Exception:
                pass

        # 5. Calculation Logic with Self-Healing Checksum Reconciliation
        total_obtained = 0.0
        total_max = 0.0
        calculated_percentage = 0.0

        if total_subjects > 0:
            total_max = sum(s["max_marks"] for s in subjects)
            subjects, total_obtained, calculated_percentage = cls._heal_checksum_discrepancies(
                subjects=subjects,
                printed_grand_total=printed_grand_total,
                printed_percentage=printed_percentage,
                total_max=total_max,
            )

        # 6. Format Display Report according to prompt specification
        exam_display = "10th" if "10" in exam_type else "12th"
        total_obtained_str = f"{total_obtained:.1f}".rstrip('0').rstrip('.')
        total_max_str = f"{total_max:.1f}".rstrip('0').rstrip('.')
        formatted_report = cls._format_display_report(
            exam_display, subjects, total_obtained, total_max, calculated_percentage
        )

        return {
            "exam": exam_display,
            "total_subjects": total_subjects,
            "subjects": subjects,
            "total_marks_obtained": total_obtained,
            "total_max_marks": total_max,
            "total_marks_display": f"{total_obtained_str}/{total_max_str}",
            "percentage": calculated_percentage,
            "formatted_report": formatted_report
        }

    @classmethod
    def _format_display_report(
        cls,
        exam_display: str,
        subjects: List[Dict[str, Any]],
        total_obtained: Any,
        total_max: Any,
        percentage: Any,
    ) -> str:
        """
        Formats structured marks table into clean markdown bulleted report.
        """
        try:
            t_obt = float(total_obtained) if total_obtained is not None else 0.0
        except Exception:
            t_obt = 0.0
        try:
            t_max = float(total_max) if total_max is not None else 0.0
        except Exception:
            t_max = 0.0
        try:
            pct = float(percentage) if percentage is not None else 0.0
        except Exception:
            pct = 0.0

        t_obt_str = f"{t_obt:.1f}".rstrip('0').rstrip('.')
        t_max_str = f"{t_max:.1f}".rstrip('0').rstrip('.')

        lines_report = [
            f"* **Exam:** {exam_display}",
            f"* **Total Subjects:** {len(subjects)}",
            "* **Subjects:**"
        ]

        for i, sub in enumerate(subjects, 1):
            s_name = sub.get("subject_name", f"Subject {i}")
            raw_val = sub.get("normalized_100")
            if raw_val is None:
                raw_val = sub.get("marks_obtained", 0)
            try:
                norm_val = f"{float(raw_val):.1f}".rstrip('0').rstrip('.')
            except Exception:
                norm_val = str(raw_val)
            lines_report.append(f"  * Subject {i} ({s_name}): {norm_val}/100")

        lines_report.append(f"* **Total Marks:** {t_obt_str}/{t_max_str}")
        lines_report.append(f"* **Percentage:** {pct:.2f}%")
        return "\n".join(lines_report)

    @classmethod
    def _heal_checksum_discrepancies(
        cls,
        subjects: List[Dict[str, Any]],
        printed_grand_total: Optional[float],
        printed_percentage: Optional[float],
        total_max: float
    ) -> Tuple[List[Dict[str, Any]], float, float]:
        """
        Self-healing checksum reconciliation.
        Verifies and auto-corrects OCR digit mistakes using mathematical constraints:
        1. sum(Subject Marks) == Grand Total
        2. (Grand Total / Max Marks) * 100 == Percentage
        """
        if not subjects:
            return subjects, (printed_grand_total or 0.0), (printed_percentage or 0.0)

        calc_sum = sum(s.get("marks_obtained", 0.0) for s in subjects)

        # 1. Reconcile Grand Total with Stated Percentage if available
        target_total = printed_grand_total
        if printed_percentage and total_max > 0:
            math_total = round((printed_percentage / 100.0) * total_max)
            if target_total is None or abs(target_total - math_total) <= 2:
                target_total = float(math_total)

        if target_total is None:
            target_total = calc_sum

        # 2. Check if subject sum matches target_total
        discrepancy = target_total - calc_sum
        if abs(discrepancy) > 0 and abs(discrepancy) <= 80 and subjects:
            # Check if a single subject can be adjusted to balance the checksum
            healed = False
            for s in subjects:
                curr = s.get("marks_obtained", 0.0)
                max_m = s.get("max_marks", 100.0)
                cand = curr + discrepancy
                if 0.0 <= cand <= max_m:
                    curr_str = str(int(curr))
                    cand_str = str(int(cand))
                    if len(curr_str) == len(cand_str):
                        diff_chars = sum(1 for a, b in zip(curr_str, cand_str) if a != b)
                        if diff_chars == 1:
                            logger.info(
                                "Self-healing parser auto-corrected subject '%s' from %s to %s (discrepancy: %s)",
                                s.get("subject_name"), curr, cand, discrepancy
                            )
                            s["marks_obtained"] = cand
                            if "normalized_100" in s:
                                s["normalized_100"] = (cand / max_m) * 100.0
                            healed = True
                            break

        final_sum = sum(s.get("marks_obtained", 0.0) for s in subjects)
        effective_total = target_total if target_total > 0 else final_sum
        effective_pct = (effective_total / total_max) * 100.0 if total_max > 0 else (printed_percentage or 0.0)

        return subjects, round(effective_total, 1), round(effective_pct, 2)

    @classmethod
    def _parse_subject_line(cls, line: str, matched_keyword: str) -> Optional[Dict[str, Any]]:
        """
        Parses a single line containing an academic subject and its numerical marks.
        """
        # 0. Isolate leading subject code so it is NEVER confused with obtained marks
        line_clean = line.strip()
        m_code = re.match(r'^\s*(\d{1,3})\s+([A-Za-z].*)$', line_clean)
        if m_code:
            rem_line = m_code.group(2)
        else:
            rem_line = line_clean

        # Pattern A: Slash format (e.g. '041 MATHEMATICS : 85 / 100' or 'ENGLISH 92/100')
        slash_match = re.search(r'([A-Za-z\s&\(\)\-\.]{3,35})[^\d\n]*?(\d{1,3})\s*/\s*(\d{2,3})', rem_line)
        if slash_match:
            sub_raw = slash_match.group(1).strip()
            sub_name = cls._clean_subject_name(sub_raw, matched_keyword)
            try:
                obt = float(slash_match.group(2))
                max_m = float(slash_match.group(3))
                if 0 <= obt <= max_m and max_m in (50, 70, 75, 80, 100, 150):
                    norm_100 = round((obt / max_m) * 100.0, 2)
                    return {
                        "subject_name": sub_name,
                        "marks_obtained": obt,
                        "max_marks": max_m,
                        "normalized_100": norm_100,
                        "display": f"{int(obt) if obt.is_integer() else obt}/{int(max_m)}"
                    }
            except Exception:
                pass

        # Pattern B: Space-separated numerical values
        # e.g. 'HINDI COURSE-A 085 100 A1' (code 002 already stripped)
        # e.g. 'MATHEMATICS 072 100 B1'
        # e.g. 'GUJARATI 100 074 PASS'
        # e.g. 'PHYSICS 055 020 075 100 B1'
        numbers = [float(n) for n in re.findall(r'\b\d{1,3}\b', rem_line)]
        if not numbers:
            return None

        # Subject name extraction: grab letters around the matched keyword
        sub_name = cls._extract_clean_subject_from_line(rem_line, matched_keyword)

        obt = None
        max_m = 100.0

        # Case B1: Three or four numbers where two add up to total
        # e.g. Theory=55, Practical=20, Total=75, Max=100
        for i in range(len(numbers)):
            for j in range(i + 1, len(numbers)):
                sum_val = numbers[i] + numbers[j]
                if sum_val in numbers:
                    obt = sum_val
                    break
            if obt is not None:
                break

        # Case B2: Max marks 100 is explicit, other number is obtained marks
        if obt is None:
            if 100.0 in numbers and len(numbers) >= 2:
                candidates = [n for n in numbers if n <= 100.0 and n != 100.0]
                if candidates:
                    # The highest score <= 100 is the obtained marks (ignoring 2-digit subject codes like 01)
                    obt = max(candidates)
                    max_m = 100.0

        # Case B3: Single valid mark <= 100
        if obt is None:
            # If line has subject code and single mark: e.g. '041 MATHEMATICS 85'
            valid_marks = [n for n in numbers if 20.0 <= n <= 100.0]
            if valid_marks:
                obt = valid_marks[-1]
                max_m = 100.0

        if obt is not None and 15.0 <= obt <= max_m:
            norm_100 = round((obt / max_m) * 100.0, 2)
            return {
                "subject_name": sub_name,
                "marks_obtained": obt,
                "max_marks": max_m,
                "normalized_100": norm_100,
                "display": f"{int(obt) if obt.is_integer() else obt}/{int(max_m)}"
            }

        return None

    @classmethod
    def _extract_from_table_layout(cls, lines: List[str]) -> List[Dict[str, Any]]:
        """
        Extracts subjects where subject names and marks are in multi-line OCR blocks.
        """
        subject_positions = []
        for i, line in enumerate(lines):
            line_lower = line.lower().strip()
            if any(k in line_lower for k in EXCLUDED_KEYWORDS) or any(k in line_lower for k in ADMIN_KEYWORDS):
                continue
            if re.search(r'\b(grand\s*total|total\s*:|performance|result|percentile)\b', line_lower):
                break
            for kw in CORE_ACADEMIC_KEYWORDS:
                if re.search(r'\b' + re.escape(kw) + r'\b', line_lower):
                    subject_positions.append((i, kw, line))
                    break

        results = []
        seen_keys = set()
        for idx, (line_idx, kw, line_str) in enumerate(subject_positions):
            next_line_idx = subject_positions[idx + 1][0] if idx + 1 < len(subject_positions) else min(len(lines), line_idx + 10)
            block_lines = lines[line_idx:next_line_idx]
            block_text = " ".join(block_lines)

            # Strip leading subject code from block text so it is never confused with obtained marks
            block_clean = re.sub(r'^\s*\d{1,3}\s*[\.\-]?\s*', '', block_text.strip())
            nums = [float(n) for n in re.findall(r'\b\d{1,3}\b', block_clean)]
            obt = None
            max_m = 100.0

            # 1. Check if two numbers sum to a third (e.g. Theory + Practical = Grand Total)
            for i_n in range(len(nums)):
                for j_n in range(i_n + 1, len(nums)):
                    sum_n = nums[i_n] + nums[j_n]
                    if sum_n in nums and 20.0 <= sum_n <= 100.0:
                        obt = sum_n
                        break
                if obt is not None:
                    break

            # 2. Otherwise pick highest valid mark <= 100 (e.g. 085 from [68, 85])
            # Exclude single-digit grade points <= 10.0
            if obt is None:
                cands = [n for n in nums if 15.0 <= n <= 100.0 and n != 100.0]
                if cands:
                    obt = max(cands)
                elif 100.0 in nums:
                    obt = 100.0

            if obt is not None and 15.0 <= obt <= max_m:
                sub_name = cls._extract_clean_subject_from_line(line_str, kw)
                canonical = sub_name.lower()
                key = "social_science" if "social" in canonical else ("science" if "science" in canonical else canonical.split()[0])
                if key not in seen_keys:
                    seen_keys.add(key)
                    norm_100 = round((obt / max_m) * 100.0, 2)
                    results.append({
                        "subject_name": sub_name,
                        "marks_obtained": obt,
                        "max_marks": max_m,
                        "normalized_100": norm_100,
                        "display": f"{int(obt) if obt.is_integer() else obt}/{int(max_m)}"
                    })
        return results

    @staticmethod
    def _clean_subject_name(raw_text: str, matched_kw: str) -> str:
        """Cleans and canonicalizes the subject name."""
        # Strip leading numerical codes (e.g. '041 MATHEMATICS' -> 'MATHEMATICS')
        cleaned = re.sub(r'^\d+\s*[\.\-]?\s*', '', raw_text.strip())
        # Strip trailing colon or dashes
        cleaned = re.sub(r'[:\-\|~_]+$', '', cleaned).strip()
        cleaned = re.sub(r'\b(ONE|TWO|THREE|FOUR|FIVE|SIX|SEVEN|EIGHT|EICHT|NINE|ZERO|TEN|HUNDRED)\b', '', cleaned, flags=re.I)
        cleaned = " ".join(cleaned.split())
        if not cleaned or len(cleaned) < 3:
            return matched_kw.title()
        return cleaned.title()

    @classmethod
    def _extract_clean_subject_from_line(cls, line: str, matched_kw: str) -> str:
        """Extracts the subject name portion from a mixed alphanumeric line."""
        # Remove numbers and grades like A1, B2 from the line to isolate the subject title
        cleaned = re.sub(r'\b\d{1,3}\b', '', line)
        cleaned = re.sub(r'\b[A-E][1-2]?\b', '', cleaned)
        cleaned = re.sub(r'\b(PASS|FAIL|COMP|DISTINCTION)\b', '', cleaned, flags=re.I)
        cleaned = re.sub(r'\b(ONE|TWO|THREE|FOUR|FIVE|SIX|SEVEN|EIGHT|EICHT|NINE|ZERO|TEN|HUNDRED)\b', '', cleaned, flags=re.I)
        cleaned = re.sub(r'[\|:;~_]+', ' ', cleaned)
        cleaned = " ".join(cleaned.split())
        return cls._clean_subject_name(cleaned, matched_kw)
