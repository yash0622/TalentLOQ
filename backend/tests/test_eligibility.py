import pytest
from app.eligibility import compute_eligibility

def test_eligibility_course_and_cgpa_pass():
    drive = {
        "eligible_courses": ["BTECH_CSE", "BCA"],
        "min_cgpa": 7.0,
        "placement_policy_flags": {
            "requires_placement_access": True,
            "requires_job_interest": True,
        },
    }
    student = {
        "course": "BTECH_CSE",
        "CGPA": 8.2,
        "placement_policy": {
            "has_placement_access": True,
            "job_interest": True,
        },
    }
    assert compute_eligibility(student, drive) is True

def test_eligibility_course_mismatch_fails():
    drive = {
        "eligible_courses": ["BTECH_CSE"],
        "min_cgpa": 6.0,
    }
    student = {
        "course": "MBA",
        "CGPA": 9.0,
    }
    assert compute_eligibility(student, drive) is False

def test_eligibility_cgpa_below_cutoff_fails():
    drive = {
        "eligible_courses": ["ALL"],
        "min_cgpa": 7.5,
    }
    student = {
        "course": "BTECH_CSE",
        "CGPA": 7.2,
    }
    assert compute_eligibility(student, drive) is False

def test_eligibility_placement_policy_flag_fails():
    drive = {
        "eligible_courses": ["ALL"],
        "min_cgpa": 6.0,
        "placement_policy_flags": {
            "requires_internship_interest": True,
        },
    }
    student = {
        "course": "BTECH_CSE",
        "CGPA": 8.0,
        "placement_policy": {
            "internship_interest": False,
        },
    }
    assert compute_eligibility(student, drive) is False
