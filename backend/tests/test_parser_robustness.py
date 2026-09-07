"""
Parser Robustness Test Suite.
Tests all 4 parsers (Resume, 10th, 12th/Diploma, UG) against real-world
OCR noise, boundary conditions, missing fields, and adversarial inputs.
"""
import pytest
from app.document_detection import (
    ResumeParser,
    TenthMarksheetParser,
    TwelfthDiplomaParser,
    UGMarksheetParser,
)


# ===================================================================
# RESUME PARSER ROBUSTNESS
# ===================================================================

class TestResumeParserRobustness:
    def test_skills_with_version_numbers_stripped(self):
        """Skills like 'React v18.2' should normalize to 'React'."""
        text = """
        John Doe
        Skills: React v18.2, Node.js v20, Python 3.12, Docker 25.0
        Languages Known: English
        """
        result = ResumeParser.parse(text)
        assert "React" in result["technical_skills"]
        assert "Node.js" in result["technical_skills"]
        assert "Python" in result["technical_skills"]
        assert "Docker" in result["technical_skills"]

    def test_skills_from_bullet_list_format(self):
        """Skills in bulleted list format should be picked up."""
        text = """
        Jane Smith
        Technical Skills:
        • Python
        • FastAPI
        • MongoDB
        • Docker
        
        Languages Known:
        English, Hindi
        """
        result = ResumeParser.parse(text)
        assert "Python" in result["technical_skills"]
        assert "FastAPI" in result["technical_skills"]
        assert "MongoDB" in result["technical_skills"]

    def test_empty_text_no_crash(self):
        """Empty string should not crash, returns empty lists."""
        result = ResumeParser.parse("")
        assert result["skills"] == []
        assert result["technical_skills"] == []
        assert result["languages"] == []
        assert result["candidate_name"] is None

    def test_programming_languages_classification(self):
        """Programming languages should appear in both tech_skills and programming_languages."""
        text = """
        Amit Patel
        Technical Skills: Python, Java, C++, Dart, JavaScript, SQL
        Languages Known: English, Hindi
        """
        result = ResumeParser.parse(text)
        for lang in ["Python", "Java", "C++", "Dart", "JavaScript", "SQL"]:
            assert lang in result["programming_languages"], f"{lang} missing from programming_languages"

    def test_soft_skills_separated_from_tech(self):
        """Soft skills should appear in soft_skills, not technical_skills."""
        text = """
        Sara Khan
        Technical Skills: Python, FastAPI
        Soft Skills: Leadership, Communication, Teamwork, Problem Solving
        Languages Known: English
        """
        result = ResumeParser.parse(text)
        assert "Leadership" in result["soft_skills"]
        assert "Communication" in result["soft_skills"]
        assert "Teamwork" in result["soft_skills"]
        assert "Problem Solving" in result["soft_skills"]
        # Soft skills should NOT leak into technical
        for s in ["Leadership", "Communication", "Teamwork"]:
            assert s not in result["technical_skills"]

    def test_candidate_name_from_certify_clause(self):
        """Name extracted from 'hereby certifies' pattern."""
        text = """
        The University of Mumbai hereby certifies that
        Rahul Vinod Kumar
        has completed the requirements
        """
        result = ResumeParser.parse(text)
        assert result["candidate_name"] == "Rahul Vinod Kumar"

    def test_candidate_name_from_label(self):
        """Name from 'Candidate Name: ...' label."""
        text = """
        Board of Secondary Education
        Candidate Name: Priya Sharma Mehta
        Roll No: 12345
        """
        result = ResumeParser.parse(text)
        assert result["candidate_name"] == "Priya Sharma Mehta"

    def test_duplicate_skills_deduplication(self):
        """Same skill in different casing/aliases should appear once."""
        text = """
        Dev User
        Skills: python, Python, PYTHON, react, React, react.js, ReactJS
        Languages Known: English
        """
        result = ResumeParser.parse(text)
        assert result["technical_skills"].count("Python") == 1
        assert result["technical_skills"].count("React") == 1

    def test_no_spoken_languages_in_tech_skills(self):
        """Spoken languages should not appear as technical skills."""
        text = """
        Dev User
        Skills: Python, JavaScript
        Languages Known: English, Hindi, Gujarati, French
        """
        result = ResumeParser.parse(text)
        for lang in ["English", "Hindi", "Gujarati", "French"]:
            assert lang not in result["technical_skills"]
            assert lang in result["languages"]


# ===================================================================
# 10TH MARKSHEET PARSER ROBUSTNESS
# ===================================================================

class TestTenthMarksheetParserRobustness:
    def test_explicit_percentage_extraction(self):
        text = """
        Gujarat Secondary and Higher Secondary Education Board (GSEB)
        Secondary School Certificate Examination
        Candidate Name: Chintan Sharma
        Percentage: 73.17%
        Passing Year: 2020
        """
        result = TenthMarksheetParser.parse(text)
        assert result["tenth_percentage"] == 73.17
        assert result["passing_year"] == 2020
        assert result["board"] == "Gujarat Secondary and Higher Secondary Education Board (GSEB)"

    def test_calculated_percentage_from_marks(self):
        """Percentage calculated from obtained/total marks."""
        text = """
        CBSE Secondary School Examination Class X
        Candidate Name: Test Student
        Grand Total: 450/500
        Result: PASS
        """
        result = TenthMarksheetParser.parse(text)
        assert result["tenth_percentage"] == 90.0

    def test_cbse_cgpa_to_percentage_conversion(self):
        """Pre-2018 CBSE CGPA * 9.5 = percentage."""
        text = """
        Central Board of Secondary Education (CBSE)
        Secondary School Examination (Class X) 2016
        Candidate Name: Old Student
        CGPA: 9.2
        """
        result = TenthMarksheetParser.parse(text)
        assert result["tenth_cgpa"] == 9.2
        assert result["tenth_percentage"] == 87.4  # 9.2 * 9.5

    def test_boundary_percentage_zero(self):
        """0% should be accepted (edge case)."""
        text = """
        CBSE Class X
        Candidate Name: Edge Case
        Percentage: 0.00%
        """
        result = TenthMarksheetParser.parse(text)
        assert result["tenth_percentage"] == 0.0

    def test_percentage_above_100_rejected(self):
        """Percentage >100 should be rejected."""
        text = """
        CBSE Class X
        Candidate Name: Invalid Case
        Percentage: 105.50%
        """
        result = TenthMarksheetParser.parse(text)
        # The explicit percentage regex won't match >100, so fallback should also reject
        assert result["tenth_percentage"] is None or result["tenth_percentage"] <= 100.0

    def test_ocr_noise_in_board_name(self):
        """GSEB should still be detected even with nearby OCR noise."""
        text = """
        Gu]arat Secondary and Higher Secondary Education Board
        GSEB SSC Exam 2021
        Candidate Name: OCR Test
        Percentage: 82.50%
        """
        result = TenthMarksheetParser.parse(text)
        assert "GSEB" in result["board"]

    def test_no_percentage_no_crash(self):
        """Missing percentage should return None, not crash."""
        text = """
        Board of Secondary Education
        Candidate Name: No Score Student
        Result: PASS
        """
        result = TenthMarksheetParser.parse(text)
        assert result["tenth_percentage"] is None

    def test_empty_text_no_crash(self):
        result = TenthMarksheetParser.parse("")
        assert result["tenth_percentage"] is None
        assert result["student_name"] is None
        assert result["passing_year"] is None


# ===================================================================
# 12TH / DIPLOMA PARSER ROBUSTNESS
# ===================================================================

class TestTwelfthDiplomaParserRobustness:
    def test_twelfth_marksheet_detection(self):
        """12th marksheet should set doc_subtype to TWELFTH_MARKSHEET."""
        text = """
        Higher Secondary Certificate Examination
        Board: Gujarat Board
        Candidate Name: Student Twelve
        Percentage: 78.40%
        Passing Year: 2022
        """
        result = TwelfthDiplomaParser.parse(text)
        assert result["document_subtype"] == "TWELFTH_MARKSHEET"
        assert result["percentage"] == 78.4
        assert result["diploma_cgpa"] is None

    def test_diploma_marksheet_detection(self):
        """Diploma marksheet should set doc_subtype to DIPLOMA_MARKSHEET."""
        text = """
        Diploma in Computer Engineering
        Gujarat Technological University
        ITM SLS Baroda
        CGPA: 7.36
        Passing Year: 2024
        Candidate Name: Diploma Student
        """
        result = TwelfthDiplomaParser.parse(text)
        assert result["document_subtype"] == "DIPLOMA_MARKSHEET"
        assert result["diploma_cgpa"] == 7.36
        assert "ITM SLS Baroda" in result["board_or_university"]

    def test_diploma_no_blind_percentage_conversion(self):
        """Diploma CGPA should NOT be auto-converted to percentage."""
        text = """
        Diploma in Engineering
        Polytechnic Board
        CGPA: 8.50
        """
        result = TwelfthDiplomaParser.parse(text)
        assert result["diploma_cgpa"] == 8.5
        # Percentage should be None unless explicitly stated
        assert result["percentage"] is None

    def test_twelfth_with_raw_percentage(self):
        """Raw percentage like '85.60%' should be picked up."""
        text = """
        Higher Secondary Education
        HSC Examination 2023
        Student Name: HSC Student
        Result: 85.60%
        """
        result = TwelfthDiplomaParser.parse(text)
        assert result["percentage"] == 85.6

    def test_year_in_words(self):
        """'Two Thousand Twenty Five' should parse as 2025."""
        text = """
        Higher Secondary Certificate
        Year of Passing: Two Thousand Twenty Five
        Candidate Name: Word Year Student
        Percentage: 70.00%
        """
        result = TwelfthDiplomaParser.parse(text)
        assert result["passing_year"] == 2025

    def test_empty_text_no_crash(self):
        result = TwelfthDiplomaParser.parse("")
        assert result["document_subtype"] == "TWELFTH_MARKSHEET"
        assert result["percentage"] is None
        assert result["diploma_cgpa"] is None
        assert result["student_name"] is None


# ===================================================================
# UG MARKSHEET PARSER ROBUSTNESS
# ===================================================================

class TestUGMarksheetParserRobustness:
    def test_vertical_table_sgpa_cgpa_disambiguation(self):
        """OCR vertical stack: SGPA header first, then CGPA header, then values."""
        text = """
        GSFC University
        Grade Report - Semester 1
        B.TECH: COMPUTER SCIENCE AND ENGINEERING
        Enrollment Number: 24BT04D231
        Student Name: Sharma Chintan Indravadan
        Result PASS
        SGPA
        CGPA
        7.96
        7.13
        """
        result = UGMarksheetParser.parse(text)
        assert result["sgpa"] == 7.96
        assert result["cgpa"] == 7.13
        assert result["sgpa"] != result["cgpa"]

    def test_reversed_vertical_table_cgpa_first(self):
        """Reversed vertical stack: CGPA header first, then SGPA."""
        text = """
        GSFC University
        Grade Report
        Enrollment Number: 24BT04D999
        CGPA
        SGPA
        8.50
        9.10
        """
        result = UGMarksheetParser.parse(text)
        assert result["cgpa"] == 8.50
        assert result["sgpa"] == 9.10

    def test_horizontal_table_sgpa_cgpa(self):
        """Horizontal row: SGPA and CGPA in same header line."""
        text = """
        GSFC University
        Grade Report
        Enrollment Number: 24BT04D888
        SGPA    CGPA
        8.20    7.80
        """
        result = UGMarksheetParser.parse(text)
        assert result["sgpa"] == 8.20
        assert result["cgpa"] == 7.80

    def test_labeled_cgpa_and_sgpa(self):
        """Standard 'CGPA: X.XX' and 'SGPA: Y.YY' labeled format."""
        text = """
        University Examination
        Bachelor of Technology
        Enrollment Number: ABC123
        Computer Science
        SGPA: 8.40
        CGPA: 7.90
        Semester: 3
        Backlogs: 0
        """
        result = UGMarksheetParser.parse(text)
        assert result["sgpa"] == 8.40
        assert result["cgpa"] == 7.90
        assert result["active_backlogs"] == 0
        assert result["current_semester"] == 3

    def test_zero_backlogs_pass_result(self):
        """'Result PASS' should correctly yield 0 backlogs."""
        text = """
        GSFC University
        B.TECH Computer Science
        Enrollment No: TEST123
        Semester: 2
        CGPA: 8.00
        Result: Pass with distinction
        """
        result = UGMarksheetParser.parse(text)
        assert result["active_backlogs"] == 0

    def test_atkt_backlogs(self):
        """ATKT count extracted correctly."""
        text = """
        GTU Examination
        B.Tech Mechanical Engineering
        CGPA: 5.50
        ATKT: 3
        """
        result = UGMarksheetParser.parse(text)
        assert result["active_backlogs"] == 3

    def test_no_backlog_info_returns_unknown(self):
        """When no backlog pattern is found, return 'UNKNOWN'."""
        text = """
        University Exam
        B.Tech
        CGPA: 7.00
        """
        result = UGMarksheetParser.parse(text)
        assert result["active_backlogs"] == "UNKNOWN"

    def test_enrollment_number_extraction(self):
        """Enrollment number with OCR noise should still parse."""
        text = """
        GSFC University
        Enrollmont Numbor: 24BT04D231
        CGPA: 7.13
        """
        result = UGMarksheetParser.parse(text)
        assert result["enrollment_number"] == "24BT04D231"

    def test_university_detection_gtu(self):
        text = "Gujarat Technological University\nB.Tech Computer\nCGPA: 8.0"
        result = UGMarksheetParser.parse(text)
        assert result["university"] == "Gujarat Technological University"

    def test_university_detection_nirma(self):
        text = "Nirma University\nB.Tech\nCGPA: 7.5"
        result = UGMarksheetParser.parse(text)
        assert result["university"] == "Nirma University"

    def test_university_detection_parul(self):
        text = "Parul University\nB.Tech\nCGPA: 6.8"
        result = UGMarksheetParser.parse(text)
        assert result["university"] == "Parul University"

    def test_branch_detection_variants(self):
        """Different engineering branches should be detected."""
        branches = {
            "computer science": "Computer Science & Engineering",
            "mechanical engineering": "Mechanical Engineering",
            "chemical engineering": "Chemical Engineering",
            "fire and safety": "Fire & Safety Engineering",
        }
        for keyword, expected_branch in branches.items():
            text = f"University\nB.Tech\n{keyword}\nCGPA: 7.0"
            result = UGMarksheetParser.parse(text)
            assert result["branch"] == expected_branch, f"Failed for '{keyword}': got {result['branch']}"

    def test_semester_roman_numerals(self):
        """Roman numeral semesters should be parsed."""
        for roman, expected in [("I", 1), ("II", 2), ("III", 3), ("IV", 4), ("V", 5)]:
            text = f"University\nB.Tech\nSemester: {roman}\nCGPA: 7.0"
            result = UGMarksheetParser.parse(text)
            assert result["current_semester"] == expected, f"Failed for {roman}"

    def test_cgpa_boundary_10(self):
        """CGPA of exactly 10.0 should be accepted."""
        text = "University\nB.Tech Computer\nCGPA: 10.0\nSemester 1"
        result = UGMarksheetParser.parse(text)
        assert result["cgpa"] == 10.0

    def test_cgpa_above_10_rejected(self):
        """CGPA > 10 should not be accepted."""
        text = "University\nB.Tech\nCGPA: 11.5"
        result = UGMarksheetParser.parse(text)
        assert result["cgpa"] is None or result["cgpa"] <= 10.0

    def test_empty_text_no_crash(self):
        result = UGMarksheetParser.parse("")
        assert result["sgpa"] is None
        assert result["cgpa"] is None
        assert result["student_name"] is None
        assert result["enrollment_number"] is None

    def test_gsfc_university_student_name_from_label(self):
        """Name from 'Student Name' label on its own line (OCR pattern)."""
        text = """
        GSFC University
        Grade Report
        Student Name
        SHARMA CHINTAN INDRAVADAN
        Enrollment Number: 24BT04D231
        CGPA: 7.13
        """
        result = UGMarksheetParser.parse(text)
        assert result["student_name"] is not None
        assert "sharma" in result["student_name"].lower()
        assert "chintan" in result["student_name"].lower()


# ===================================================================
# CROSS-PARSER EDGE CASES
# ===================================================================

class TestCrossParserEdgeCases:
    def test_whitespace_only_text(self):
        """All parsers should handle whitespace-only text gracefully."""
        for parser in [ResumeParser, TenthMarksheetParser, TwelfthDiplomaParser, UGMarksheetParser]:
            result = parser.parse("   \n\n\t  \n  ")
            assert isinstance(result, dict)

    def test_very_long_text_no_hang(self):
        """Parsers should handle very long text without hanging."""
        long_text = "word " * 10000
        for parser in [ResumeParser, TenthMarksheetParser, TwelfthDiplomaParser, UGMarksheetParser]:
            result = parser.parse(long_text)
            assert isinstance(result, dict)

    def test_special_characters_no_crash(self):
        """Special characters should not crash parsers."""
        nasty_text = "R C TM EUR GBP YEN +-x / != <= >= inf pi sqrt sum prod partial nabla in notin empty intersect union subset superset"
        for parser in [ResumeParser, TenthMarksheetParser, TwelfthDiplomaParser, UGMarksheetParser]:
            result = parser.parse(nasty_text)
            assert isinstance(result, dict)

    def test_numeric_injection_attempt(self):
        """Attempt to inject false academic values via embedded text."""
        text = """
        CGPA: 10.0 SGPA: 10.0 Percentage: 100%
        Active Backlogs: 99
        """
        # These values should parse but be constrained by validation
        ug_result = UGMarksheetParser.parse(text)
        assert isinstance(ug_result, dict)
        # The parser itself doesn't enforce business rules beyond range checks


# ===================================================================
# ENHANCEMENTS & NEW COVERAGE VALIDATION
# ===================================================================

class TestParserEnhancements:
    def test_dynamic_skill_extraction_filters_noise_words(self):
        """Noise words (locations, months, action verbs, numbers) should NOT be extracted as skills."""
        text = """
        Candidate Name: Test User
        Technical Skills: Python, FastAPI, Vadodara, Ahmedabad, Fresher, January, 101, Developed, Intern
        Languages Known: English
        """
        result = ResumeParser.parse(text)
        skills_lower = [s.lower() for s in result["technical_skills"]]
        assert "python" in skills_lower
        assert "fastapi" in skills_lower
        assert "vadodara" not in skills_lower
        assert "ahmedabad" not in skills_lower
        assert "fresher" not in skills_lower
        assert "january" not in skills_lower
        assert "101" not in skills_lower
        assert "developed" not in skills_lower
        assert "intern" not in skills_lower

    def test_ug_marksheet_course_no_blind_default(self):
        """Course should be None if no course keyword is present, not blindly defaulted to B.Tech."""
        text = """
        University of Baroda
        Grade Sheet - Semester 3
        Enrollment Number: ABC999
        SGPA: 8.5
        CGPA: 8.2
        """
        result = UGMarksheetParser.parse(text)
        assert result["course"] is None

    def test_ug_marksheet_expanded_courses(self):
        """Test detection of BCA, MCA, B.E., M.Tech, M.Sc, MBA, B.Pharm."""
        cases = [
            ("Bachelor of Computer Applications - Semester 2", "BCA"),
            ("Master of Computer Applications Grade Report", "MCA"),
            ("Bachelor of Engineering in Electronics", "B.E."),
            ("M.Tech Computer Engineering", "M.Tech"),
            ("Bachelor of Science in Chemistry", "B.Sc"),
            ("Master of Science in Physics", "M.Sc"),
            ("Bachelor of Pharmacy Semester 4", "B.Pharm"),
            ("Master of Business Administration", "MBA"),
        ]
        for snippet, expected_course in cases:
            res = UGMarksheetParser.parse(snippet)
            assert res["course"] == expected_course, f"Expected {expected_course} for '{snippet}', got {res['course']}"

    def test_ug_marksheet_expanded_branches(self):
        """Test detection of ECE, EEE, Civil, IT, AI & ML, Automobile, Biomedical."""
        cases = [
            ("Electronics & Communication Engineering", "Electronics & Communication Engineering"),
            ("Electrical and Electronics Engineering", "Electrical & Electronics Engineering"),
            ("Civil Engineering Department", "Civil Engineering"),
            ("Information Technology Department", "Information Technology"),
            ("Artificial Intelligence and Machine Learning", "Artificial Intelligence & ML"),
            ("Automobile Engineering", "Automobile Engineering"),
            ("Biomedical Engineering", "Biomedical Engineering"),
        ]
        for snippet, expected_branch in cases:
            res = UGMarksheetParser.parse(snippet)
            assert res["branch"] == expected_branch, f"Expected {expected_branch} for '{snippet}', got {res['branch']}"

    def test_ug_marksheet_expanded_universities(self):
        """Test detection of Charusat, Ganpat, LJ, Marwadi, DDU, SPU, MSU Baroda."""
        cases = [
            ("Charusat University Changa", "Charotar University of Science & Technology"),
            ("Ganpat University Mehsana", "Ganpat University"),
            ("LJ University Ahmedabad", "LJ University"),
            ("Marwadi University Rajkot", "Marwadi University"),
            ("Dharmsinh Desai University Nadiad", "Dharmsinh Desai University"),
            ("Sardar Patel University VVN", "Sardar Patel University"),
            ("The Maharaja Sayajirao University of Baroda", "The Maharaja Sayajirao University of Baroda"),
        ]
        for snippet, expected_uni in cases:
            res = UGMarksheetParser.parse(snippet)
            assert res["university"] == expected_uni, f"Expected {expected_uni} for '{snippet}', got {res['university']}"

    def test_twelfth_diploma_extended_years_in_words(self):
        """Test 2026 and 2030 parsing from words."""
        text_2026 = "Higher Secondary Examination\nYear of Passing: Two Thousand Twenty Six\nPercentage: 80%"
        res_2026 = TwelfthDiplomaParser.parse(text_2026)
        assert res_2026["passing_year"] == 2026

        text_2030 = "Diploma in Engineering\nYear of Passing: Two Thousand Thirty\nCGPA: 8.5"
        res_2030 = TwelfthDiplomaParser.parse(text_2030)
        assert res_2030["passing_year"] == 2030

    def test_ocr_pre_normalization_fixes_typos(self):
        """OCR artifacts like 'rosult', 'semostar', 'porcentage' should be normalized."""
        text = """
        GSFC Univorsity
        Grade Roport
        Semostar: 4
        Student Name: Chintan Sharma
        Rosult: PASS
        Porcentage: 85.50%
        """
        tenth_res = TenthMarksheetParser.parse(text)
        assert tenth_res["tenth_percentage"] == 85.50

        ug_res = UGMarksheetParser.parse(text)
        assert ug_res["current_semester"] == 4
        assert ug_res["active_backlogs"] == 0

    def test_advanced_skill_noise_filtering(self):
        """School names, company suffixes, degrees, ordinals, and course codes must not leak into skills."""
        text = """
        Candidate Name: Advanced Filter Test
        Technical Skills: Python, Docker, My School Name Here, Infosys Ltd, 3rd Year, CS101, B.Tech 2024
        Languages Known: English
        """
        result = ResumeParser.parse(text)
        skills_lower = [s.lower() for s in result["technical_skills"]]
        assert "python" in skills_lower
        assert "docker" in skills_lower
        assert "my school name here" not in skills_lower
        assert "infosys ltd" not in skills_lower
        assert "3rd year" not in skills_lower
        assert "cs101" not in skills_lower
        assert "b.tech 2024" not in skills_lower

    def test_ocr_digit_and_decimal_repairs(self):
        """OCR substitutions like '7.l3' for 7.13, '8.O' for 8.0, and '2O24' for 2024 should be repaired."""
        text = """
        GSFC University
        Grade Report
        Passing Year: 2O24
        CGPA: 7.l3
        SGPA: 8.O
        Enrollment Number: 24BT04D231
        """
        ug_res = UGMarksheetParser.parse(text)
        assert ug_res["cgpa"] == 7.13
        assert ug_res["sgpa"] == 8.0

        tenth_text = "Board of Secondary Education\nPassing Year: 2O24\nPercentage: 85.l0%"
        tenth_res = TenthMarksheetParser.parse(tenth_text)
        assert tenth_res["passing_year"] == 2024
        assert tenth_res["tenth_percentage"] == 85.10

    def test_resume_platform_links_extraction(self):
        """ResumeParser should accurately extract LinkedIn, GitHub, LeetCode, Codeforces, HackerRank, Portfolio."""
        text = """
        CHINTAN SHARMA
        Vadodara, Gujarat, India | +91 8238089207 | sharmachintan585@gmail.com
        linkedin.com/in/chintan-sharma-a4a673357 | github.com/Chintannn-c
        LeetCode: leetcode.com/u/chintan_coder | CodeChef: codechef.com/users/chintan_chef
        Codeforces: codeforces.com/profile/chintan_cf | HackerRank: hackerrank.com/chintan_hr
        Portfolio: https://chintansharma.vercel.app
        Technical Skills: Python, FastAPI, Flutter
        """
        result = ResumeParser.parse(text)
        links = result.get("social_links", {})
        assert "linkedin" in links
        assert "chintan-sharma-a4a673357" in links["linkedin"]
        assert links["linkedin"].startswith("https://")

        assert "github" in links
        assert "Chintannn-c" in links["github"]
        assert links["github"].startswith("https://")

        assert "leetcode" in links
        assert "chintan_coder" in links["leetcode"]

        assert "codechef" in links
        assert "chintan_chef" in links["codechef"]

        assert "codeforces" in links
        assert "chintan_cf" in links["codeforces"]

        assert "hackerrank" in links
        assert "chintan_hr" in links["hackerrank"]

        assert "portfolio" in links
        assert "chintansharma.vercel.app" in links["portfolio"]

        # Convenience top-level fields
        assert result.get("linkedin_url") == links["linkedin"]
        assert result.get("github_url") == links["github"]
        assert result.get("leetcode_url") == links["leetcode"]
        assert result.get("portfolio_url") == links["portfolio"]

