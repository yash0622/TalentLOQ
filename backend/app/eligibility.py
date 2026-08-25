from typing import Dict, Any

def compute_eligibility(student: Dict[str, Any], drive: Dict[str, Any]) -> bool:
    """
    Computes whether a student candidate meets all eligibility criteria for a placement drive.
    Returns True if ALL conditions pass; otherwise False.

    Checks:
    1. Student course/degree in drive["eligible_courses"] (or if "ALL" present).
    2. Student CGPA >= drive["min_cgpa"].
    3. Student placement policy flags satisfy drive["placement_policy_flags"].
    """
    if not student or not drive:
        return False

    # 1. Course Match Check
    eligible_courses = drive.get("eligible_courses", ["ALL"])
    if isinstance(eligible_courses, list) and len(eligible_courses) > 0:
        normalized_courses = [str(c).upper().strip() for c in eligible_courses]
        if "ALL" not in normalized_courses and "*" not in normalized_courses:
            student_course = str(student.get("course", student.get("degree", "BTECH_CSE"))).upper().strip()
            if student_course not in normalized_courses:
                return False

    # 2. Minimum CGPA Check
    drive_min_cgpa = float(drive.get("min_cgpa", 0.0))
    student_cgpa = float(student.get("CGPA", student.get("cgpa", 0.0)))
    if student_cgpa < drive_min_cgpa:
        return False

    # 3. Placement Policy Flags Check
    drive_flags = drive.get("placement_policy_flags", {})
    if isinstance(drive_flags, dict):
        student_policy = student.get("placement_policy", {})
        if not isinstance(student_policy, dict):
            student_policy = {}

        # Requires placement access flag
        if drive_flags.get("requires_placement_access", False):
            if not student_policy.get("has_placement_access", student.get("has_placement_access", True)):
                return False

        # Requires placement eligible flag
        if drive_flags.get("requires_placement_eligible", False):
            if not student_policy.get("is_placement_eligible", student.get("is_placement_eligible", True)):
                return False

        # Requires job interest flag
        if drive_flags.get("requires_job_interest", False):
            if not student_policy.get("job_interest", student.get("job_interest", True)):
                return False

        # Requires internship interest flag
        if drive_flags.get("requires_internship_interest", False):
            if not student_policy.get("internship_interest", student.get("internship_interest", True)):
                return False

    return True
