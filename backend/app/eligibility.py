import re
from typing import Dict, Any, List

# Canonical aliases for standard academic branches and degrees
FAMILY_ALIASES = {
    "CS": [
        "CSE", "CS", "COMPUTER SCIENCE", "COMPUTER SCIENCE & ENGINEERING",
        "COMPUTER SCIENCE AND ENGINEERING", "COMPUTER SCIENCE ENGINEERING",
        "BTECH CSE", "B TECH CSE", "BTECH IN COMPUTER SCIENCE",
        "B TECH IN COMPUTER SCIENCE", "BCA", "MCA", "SOFTWARE ENGINEERING",
        "BTECH_CSE", "BTECH_IT", "INFORMATION TECHNOLOGY", "IT",
    ],
    "IT": [
        "IT", "INFORMATION TECHNOLOGY", "BTECH IT", "B TECH IT",
        "BTECH IN INFORMATION TECHNOLOGY", "BTECH_IT",
    ],
    "MECH": [
        "MECH", "MECHANICAL", "MECHANICAL ENGINEERING", "BTECH MECH",
        "B TECH MECH", "BTECH_MECH",
    ],
    "CIVIL": [
        "CIVIL", "CIVIL ENGINEERING", "BTECH CIVIL", "B TECH CIVIL",
        "BTECH_CIVIL",
    ],
    "ELECTRICAL": [
        "EEE", "EE", "ELECTRICAL", "ELECTRICAL ENGINEERING", "BTECH EE",
    ],
    "ELECTRONICS": [
        "ECE", "EC", "ELECTRONICS", "ELECTRONICS AND COMMUNICATION",
        "ELECTRONICS & COMMUNICATION", "BTECH ECE",
    ],
    "CHEMICAL": [
        "CHEMICAL", "CHEMICAL ENGINEERING", "BTECH CHEMICAL",
    ],
    "BIOTECH": [
        "BIOTECH", "BIOTECHNOLOGY", "BIO TECHNOLOGY",
    ],
}


def _normalize_token(text: Any) -> str:
    if text is None:
        return ""
    cleaned = re.sub(r'[\._\-/&]', ' ', str(text))
    cleaned = re.sub(r'\s+', ' ', cleaned).strip().upper()
    return cleaned


def _is_token_match(a: str, b: str) -> bool:
    if not a or not b:
        return False
    if a == b:
        return True
    if len(a) <= 3 or len(b) <= 3:
        return bool(re.search(rf'\b{re.escape(a)}\b', b) or re.search(rf'\b{re.escape(b)}\b', a))
    return a in b or b in a


def _matches_course(student_terms: List[str], required_courses: List[str]) -> bool:
    if not required_courses:
        return True

    norm_required = [_normalize_token(c) for c in required_courses if c]
    if not norm_required or any(k in norm_required for k in ["ALL", "*", "ANY", "ALL COURSES"]):
        return True

    norm_student = [_normalize_token(t) for t in student_terms if t and str(t).lower() not in ("none", "null", "")]
    if not norm_student:
        # If student hasn't specified any course yet, don't arbitrarily disqualify
        return True

    for req in norm_required:
        # 1. Direct term match
        if any(_is_token_match(req, st) for st in norm_student):
            return True

        # 2. Canonical family alias overlap
        for fam_key, aliases in FAMILY_ALIASES.items():
            req_in_fam = any(_is_token_match(req, a) for a in aliases)
            if req_in_fam:
                if any(any(_is_token_match(a, st) for a in aliases) for st in norm_student):
                    return True

    return False


def compute_eligibility(student: Dict[str, Any], drive: Dict[str, Any]) -> bool:
    """
    Computes whether a student candidate meets all eligibility criteria for a placement drive.
    Returns True if ALL conditions pass; otherwise False.

    Checks:
    1. Student course/degree/branch matches drive["eligible_courses"] (or if "ALL" present).
    2. Student CGPA >= drive["min_cgpa"].
    3. Student placement policy flags satisfy drive["placement_policy_flags"].
    """
    if not student or not drive:
        return False

    # 1. Course Match Check
    eligible_courses = drive.get("eligible_courses") or ["ALL"]
    if isinstance(eligible_courses, list) and len(eligible_courses) > 0:
        # Gather all possible academic descriptors from student
        verified_fields = student.get("verified_fields") or {}
        student_terms = [
            student.get("branch"),
            student.get("course"),
            student.get("degree"),
            student.get("education"),
            verified_fields.get("branch", {}).get("value") if isinstance(verified_fields.get("branch"), dict) else verified_fields.get("branch"),
            verified_fields.get("course", {}).get("value") if isinstance(verified_fields.get("course"), dict) else verified_fields.get("course"),
            verified_fields.get("degree", {}).get("value") if isinstance(verified_fields.get("degree"), dict) else verified_fields.get("degree"),
        ]
        if not _matches_course(student_terms, eligible_courses):
            return False

    # 2. Minimum CGPA Check
    drive_min_cgpa = float(drive.get("min_cgpa") or drive.get("cgpa_criteria") or 0.0)
    student_cgpa = float(student.get("CGPA") or student.get("cgpa") or 0.0)
    if student_cgpa < drive_min_cgpa:
        return False

    # 3. Active Backlogs Check
    max_backlogs = drive.get("max_backlogs")
    if max_backlogs is not None:
        try:
            max_b_val = int(max_backlogs)
            student_backlogs = int(student.get("active_backlogs") or 0)
            if student_backlogs > max_b_val:
                return False
        except (ValueError, TypeError):
            pass
    elif drive.get("allow_backlogs") is False:
        if int(student.get("active_backlogs") or 0) > 0:
            return False

    # 4. 10th Standard Cutoff Check
    drive_min_tenth = drive.get("min_tenth_percentage") or drive.get("tenth_cutoff") or drive.get("min_10th")
    if drive_min_tenth is not None:
        try:
            min_tenth_val = float(drive_min_tenth)
            student_tenth = float(student.get("tenth_percentage") or 0.0)
            if student_tenth > 0 and student_tenth < min_tenth_val:
                return False
        except (ValueError, TypeError):
            pass

    # 5. 12th Standard / Diploma Cutoff Check
    drive_min_twelfth = drive.get("min_twelfth_percentage") or drive.get("twelfth_cutoff") or drive.get("min_12th")
    if drive_min_twelfth is not None:
        try:
            min_twelfth_val = float(drive_min_twelfth)
            student_twelfth = float(student.get("twelfth_percentage") or 0.0)
            student_diploma = float(student.get("diploma_cgpa") or 0.0) * 9.5
            effective_secondary = student_twelfth if student_twelfth > 0 else student_diploma
            if effective_secondary > 0 and effective_secondary < min_twelfth_val:
                return False
        except (ValueError, TypeError):
            pass

    # 6. Placement Policy Flags Check
    drive_flags = drive.get("placement_policy_flags", {})
    if isinstance(drive_flags, dict):
        student_policy = student.get("placement_policy", {})
        if not isinstance(student_policy, dict):
            student_policy = {}

        if drive_flags.get("requires_placement_access", False):
            if not student_policy.get("has_placement_access", student.get("has_placement_access", True)):
                return False

        if drive_flags.get("requires_placement_eligible", False):
            if not student_policy.get("is_placement_eligible", student.get("is_placement_eligible", True)):
                return False

        if drive_flags.get("requires_job_interest", False):
            if not student_policy.get("job_interest", student.get("job_interest", True)):
                return False

        if drive_flags.get("requires_internship_interest", False):
            if not student_policy.get("internship_interest", student.get("internship_interest", True)):
                return False

    return True


def evaluate_eligibility_gate(student: Dict[str, Any], drive: Dict[str, Any]) -> Dict[str, Any]:
    """
    Deterministic academic eligibility gate evaluator.
    Evaluates student academic profile against drive cutoff criteria.
    Returns boolean status, passed checks, and disqualifying reasons.
    """
    if not student or not drive:
        return {"is_eligible": False, "passed": [], "disqualifications": ["Missing student or drive profile"]}

    passed = []
    disqualifications = []

    # 1. Course Match
    eligible_courses = drive.get("eligible_courses") or ["ALL"]
    verified_fields = student.get("verified_fields") or {}
    student_terms = [
        student.get("branch"),
        student.get("course"),
        student.get("degree"),
        student.get("education"),
        verified_fields.get("branch", {}).get("value") if isinstance(verified_fields.get("branch"), dict) else verified_fields.get("branch"),
        verified_fields.get("course", {}).get("value") if isinstance(verified_fields.get("course"), dict) else verified_fields.get("course"),
    ]
    if _matches_course(student_terms, eligible_courses):
        passed.append(f"Course '{student.get('branch') or student.get('course') or 'General'}' matches drive eligibility")
    else:
        disqualifications.append(f"Course does not match required courses: {eligible_courses}")

    # 2. CGPA Cutoff
    drive_min_cgpa = float(drive.get("min_cgpa") or drive.get("cgpa_criteria") or 0.0)
    student_cgpa = float(student.get("CGPA") or student.get("cgpa") or 0.0)
    if student_cgpa >= drive_min_cgpa:
        passed.append(f"CGPA {student_cgpa:.2f} meets minimum {drive_min_cgpa:.2f}")
    else:
        disqualifications.append(f"CGPA {student_cgpa:.2f} is below required minimum {drive_min_cgpa:.2f}")

    # 3. Active Backlogs
    max_backlogs = drive.get("max_backlogs")
    student_backlogs = int(student.get("active_backlogs") or 0)
    if max_backlogs is not None:
        try:
            if student_backlogs <= int(max_backlogs):
                passed.append(f"Backlogs ({student_backlogs}) within limit ({max_backlogs})")
            else:
                disqualifications.append(f"Active backlogs ({student_backlogs}) exceeds limit ({max_backlogs})")
        except (ValueError, TypeError):
            pass
    elif drive.get("allow_backlogs") is False and student_backlogs > 0:
        disqualifications.append(f"Drive does not allow backlogs, candidate has {student_backlogs}")
    else:
        passed.append("Backlog criteria satisfied")

    # 4. 10th & 12th Cutoffs
    drive_min_10 = drive.get("min_tenth_percentage") or drive.get("tenth_cutoff") or drive.get("min_10th")
    if drive_min_10 is not None:
        student_10 = float(student.get("tenth_percentage") or 0.0)
        if student_10 >= float(drive_min_10) or student_10 == 0:
            passed.append(f"10th Grade ({student_10}%) meets cutoff ({drive_min_10}%)")
        else:
            disqualifications.append(f"10th Grade ({student_10}%) below cutoff ({drive_min_10}%)")

    drive_min_12 = drive.get("min_twelfth_percentage") or drive.get("twelfth_cutoff") or drive.get("min_12th")
    if drive_min_12 is not None:
        student_12 = float(student.get("twelfth_percentage") or 0.0)
        student_dip = float(student.get("diploma_cgpa") or 0.0) * 9.5
        eff_sec = student_12 if student_12 > 0 else student_dip
        if eff_sec >= float(drive_min_12) or eff_sec == 0:
            passed.append(f"12th/Diploma ({eff_sec:.1f}%) meets cutoff ({drive_min_12}%)")
        else:
            disqualifications.append(f"12th/Diploma ({eff_sec:.1f}%) below cutoff ({drive_min_12}%)")

    return {
        "is_eligible": len(disqualifications) == 0,
        "passed": passed,
        "disqualifications": disqualifications,
    }

