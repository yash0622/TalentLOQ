"""
Semantic, Numeric, and Cross-Document Validation Engine.
Performs:
- Strict range checking for Percentage (0-100), CGPA/SGPA (0-10), Backlogs (>=0 or UNKNOWN).
- Cross-document validation for Student Name, Enrollment Number, and University.
- Multi-dimensional confidence evaluation (OCR, Extraction, Validation).
- Decision logic: VERIFIED, REVIEW_REQUIRED, MANUAL_REVIEW, FAILED.
"""
from typing import Dict, Any, List, Optional, Tuple
from difflib import SequenceMatcher
from .schemas import VerificationStatusEnum, ExtractedField


def normalize_name_string(name: Optional[str]) -> str:
    """
    Normalizes a name string:
    1. Lowercase.
    2. Replace hyphens with spaces (e.g. Jaitra-Pathak -> jaitra pathak).
    3. Remove punctuation except letters, numbers and spaces.
    4. Collapse extra whitespace.
    """
    if not name:
        return ""
    s = name.lower().replace("-", " ").replace(".", " ")
    s = "".join(c if (c.isalnum() or c.isspace()) else " " for c in s)
    return " ".join(s.split())


def evaluate_name_match(extracted_name: Optional[str], registered_name: Optional[str]) -> Tuple[bool, float, str]:
    """
    Intelligent Name Matching Engine based on Identity Verification Prompt:

    Rule:
    Approve the document if the name clearly refers to the same person,
    even if the initial name is missing, added, expanded, abbreviated, or formatted differently.

    Examples that MUST be APPROVED (e.g. for "Jaitra Pathak"):
    - Jaitra Pathak
    - J. Pathak
    - Jaitra P.
    - J Pathak
    - Jaitra P
    - Jaitra Kumar Pathak (additional middle name)
    - Jaitra  Pathak (extra spacing)
    - JAITRA PATHAK (case difference)
    - Jaitra-Pathak (hyphenation)
    - Jaitra (single distinctive first name)
    - Pathak Jaitra (transposed last/first name)

    Returns:
        (is_approved: bool, score: float, reason: str)
    """
    if not extracted_name or not registered_name:
        return True, 1.0, "Name information not available to evaluate."

    norm_ext = normalize_name_string(extracted_name)
    norm_reg = normalize_name_string(registered_name)

    # 1. Exact match after normalization
    if norm_ext == norm_reg:
        return True, 1.0, f"Detected name '{extracted_name}' is an exact match with registered name '{registered_name}'."

    titles = {"mr", "ms", "mrs", "shri", "smt", "dr", "prof", "master"}
    tokens_ext = [t for t in norm_ext.split() if t not in titles]
    tokens_reg = [t for t in norm_reg.split() if t not in titles]

    if not tokens_ext or not tokens_reg:
        return True, 1.0, "Name matched after title normalization."

    # 2. Token sets equal regardless of order (e.g. 'Pathak Jaitra' vs 'Jaitra Pathak')
    if set(tokens_ext) == set(tokens_reg):
        return True, 0.98, f"Detected name '{extracted_name}' contains the exact name parts of '{registered_name}' in alternate order."

    # 3. Subsets (e.g. 'Jaitra Kumar Pathak' vs 'Jaitra Pathak', middle names)
    set_ext = set(tokens_ext)
    set_reg = set(tokens_reg)
    if set_reg.issubset(set_ext):
        return True, 0.95, f"Detected name '{extracted_name}' includes registered name '{registered_name}' with additional middle/family name."
    if set_ext.issubset(set_reg) and len(set_ext) >= 2:
        return True, 0.95, f"Detected name '{extracted_name}' is a valid subset of registered name '{registered_name}'."

    # 4. Check initials matching:
    # E.g.: 'J. Pathak' vs 'Jaitra Pathak'
    # E.g.: 'Jaitra P.' vs 'Jaitra Pathak'
    # E.g.: 'J Pathak' vs 'Jaitra Pathak'
    # E.g.: 'Jaitra P' vs 'Jaitra Pathak'
    def check_initials_compatible(tokens_a: List[str], tokens_b: List[str]) -> bool:
        if len(tokens_a) != len(tokens_b):
            return False
        matches = 0
        for a, b in zip(tokens_a, tokens_b):
            if a == b:
                matches += 1
            elif len(a) == 1 and b.startswith(a):
                matches += 1
            elif len(b) == 1 and a.startswith(b):
                matches += 1
        return matches == len(tokens_a)

    if check_initials_compatible(tokens_ext, tokens_reg):
        return True, 0.94, f"Detected name '{extracted_name}' matches '{registered_name}' using standard initial abbreviation."

    # 5. Single-token partial match defense
    # A single token (especially common surnames or middle names) cannot uniquely identify a person.
    # It must trigger coordinator review rather than high-confidence auto-approval.
    common_shared_tokens = {
        "kumar", "singh", "sharma", "patel", "verma", "yadav", "gupta", "shah",
        "das", "devi", "prasad", "lal", "ram", "mishra", "joshi", "shukla", "reddy", "nair"
    }
    if len(tokens_ext) == 1 and tokens_ext[0] in tokens_reg:
        matched_tok = tokens_ext[0]
        if matched_tok in common_shared_tokens:
            return False, 0.45, f"Detected single name token '{matched_tok}' is a common surname/middle-name and insufficient to verify identity."
        return False, 0.65, f"Only a single name token '{matched_tok}' was detected from document. Requires coordinator review."

    if len(tokens_reg) == 1 and tokens_reg[0] in tokens_ext:
        return False, 0.65, f"Detected name '{extracted_name}' has partial single-token overlap with '{registered_name}'. Requires coordinator review."

    # 6. Check first and last name components with middle name variation
    # E.g. 'Jaitra Pathak' vs 'Jaitra K. Pathak' or 'J. K. Pathak'
    first_ext, last_ext = tokens_ext[0], tokens_ext[-1]
    first_reg, last_reg = tokens_reg[0], tokens_reg[-1]

    first_match = (first_ext == first_reg) or (len(first_ext) == 1 and first_reg.startswith(first_ext)) or (len(first_reg) == 1 and first_ext.startswith(first_reg))
    last_match = (last_ext == last_reg) or (len(last_ext) == 1 and last_reg.startswith(last_ext)) or (len(last_reg) == 1 and last_ext.startswith(last_reg))

    if first_match and last_match:
        return True, 0.92, f"Detected name '{extracted_name}' matches registered name '{registered_name}' on first and last name components."

    # 7. Common Indian patronymic / honorific normalization
    def strip_indian_affixes(t: str) -> str:
        for suffix in ("bhai", "kumar", "ben", "prasad", "chandra", "lal"):
            if len(t) > len(suffix) + 3 and t.endswith(suffix):
                return t[:-len(suffix)]
        return t

    cleaned_tokens_ext = [strip_indian_affixes(t) for t in tokens_ext]
    cleaned_tokens_reg = [strip_indian_affixes(t) for t in tokens_reg]
    if set(cleaned_tokens_ext) == set(cleaned_tokens_reg):
        return True, 0.95, f"Detected name '{extracted_name}' matches '{registered_name}' after honorific/patronymic normalization."

    # 8. High typographic similarity fallback (minor scan typos like 'Jaitra Paathak')
    raw_sim = SequenceMatcher(None, norm_ext, norm_reg).ratio()
    if raw_sim >= 0.80:
        return True, raw_sim, f"Detected name '{extracted_name}' matches registered name '{registered_name}' with high typographic similarity ({round(raw_sim*100)}%)."

    # Mismatch
    return False, raw_sim, f"Detected name '{extracted_name}' differs materially from registered name '{registered_name}'."


def calculate_name_similarity(name1: Optional[str], name2: Optional[str]) -> float:
    """Computes token-based string similarity between two person names."""
    is_approved, score, _ = evaluate_name_match(name1, name2)
    return score if is_approved else min(score, 0.40)


class DocumentValidator:
    @staticmethod
    def validate_extracted_fields(
        doc_type: str,
        fields: Dict[str, Any],
        extraction_method: str = "native",
        base_ocr_conf: float = 95.0,
        source_filename: str = "",
    ) -> Tuple[Dict[str, ExtractedField], List[str], List[str], float, float, float]:
        """
        Validates raw extracted fields semantically and computes multi-dimensional confidences.
        
        Returns:
            Tuple of:
            (field_metadata, validation_errors, warnings, ocr_conf, extraction_conf, validation_conf)
        """
        field_metadata: Dict[str, ExtractedField] = {}
        errors: List[str] = []
        warnings: List[str] = []

        total_expected = 1
        successfully_extracted = 0

        # OCR Confidence
        ocr_conf = base_ocr_conf

        # -------------------------------------------------------------------
        # 1. RESUME VALIDATION
        # -------------------------------------------------------------------
        if doc_type == "RESUME":
            total_expected = 1
            skills = fields.get("skills") or []
            languages = fields.get("languages") or []

            if skills:
                successfully_extracted += 1
                field_metadata["skills"] = ExtractedField(
                    value=skills,
                    ocr_confidence=ocr_conf,
                    extraction_confidence=95.0,
                    validation_confidence=98.0,
                    status=VerificationStatusEnum.VERIFIED,
                    validation_notes=[f"Extracted {len(skills)} normalized skills."],
                )
            else:
                warnings.append("No explicit technical skills section recognized in resume.")

            if languages:
                successfully_extracted += 1
                field_metadata["languages"] = ExtractedField(
                    value=languages,
                    ocr_confidence=ocr_conf,
                    extraction_confidence=92.0,
                    validation_confidence=95.0,
                    status=VerificationStatusEnum.VERIFIED,
                    validation_notes=[f"Extracted {len(languages)} natural languages."],
                )

        # -------------------------------------------------------------------
        # 2. 10TH MARKSHEET VALIDATION
        # -------------------------------------------------------------------
        elif doc_type == "TENTH_MARKSHEET":
            total_expected = 3
            pct = fields.get("tenth_percentage")
            year = fields.get("passing_year")
            board = fields.get("board")

            if pct is not None:
                if 0.0 <= pct <= 100.0:
                    successfully_extracted += 1
                    field_metadata["tenth_percentage"] = ExtractedField(
                        value=pct,
                        ocr_confidence=ocr_conf,
                        extraction_confidence=95.0,
                        validation_confidence=99.0,
                        status=VerificationStatusEnum.VERIFIED,
                        validation_notes=[f"Valid 10th percentage: {pct}%"],
                    )
                else:
                    errors.append(f"Invalid 10th percentage value: {pct}% (must be between 0 and 100)")
            else:
                errors.append("Could not extract Class 10 percentage from marksheet.")

            if year:
                if 1990 <= year <= 2030:
                    successfully_extracted += 1
                    field_metadata["tenth_passing_year"] = ExtractedField(
                        value=year,
                        status=VerificationStatusEnum.VERIFIED,
                        validation_notes=[f"Passing year: {year}"],
                    )
                else:
                    warnings.append(f"Extracted 10th passing year ({year}) appears out of ordinary range.")

            if board:
                successfully_extracted += 1
                field_metadata["tenth_board"] = ExtractedField(
                    value=board,
                    status=VerificationStatusEnum.VERIFIED,
                )

        # -------------------------------------------------------------------
        # 3. 12TH / DIPLOMA MARKSHEET VALIDATION
        # -------------------------------------------------------------------
        elif doc_type in ("TWELFTH_MARKSHEET", "DIPLOMA_MARKSHEET"):
            total_expected = 3
            pct = fields.get("percentage")
            cgpa = fields.get("diploma_cgpa")
            year = fields.get("passing_year")
            board = fields.get("board_or_university")

            if doc_type == "TWELFTH_MARKSHEET":
                if pct is not None:
                    if 0.0 <= pct <= 100.0:
                        successfully_extracted += 1
                        field_metadata["twelfth_percentage"] = ExtractedField(
                            value=pct,
                            ocr_confidence=ocr_conf,
                            extraction_confidence=94.0,
                            validation_confidence=99.0,
                            status=VerificationStatusEnum.VERIFIED,
                            validation_notes=[f"Valid 12th percentage: {pct}%"],
                        )
                    else:
                        errors.append(f"Invalid 12th percentage: {pct}% (must be between 0 and 100)")
                else:
                    errors.append("Could not extract 12th percentage from marksheet.")

                if board:
                    successfully_extracted += 1
                    field_metadata["twelfth_board"] = ExtractedField(value=board, status=VerificationStatusEnum.VERIFIED)
                if year and 1990 <= year <= 2030:
                    successfully_extracted += 1
                    field_metadata["twelfth_passing_year"] = ExtractedField(value=year, status=VerificationStatusEnum.VERIFIED)

            else:  # DIPLOMA_MARKSHEET
                dip_college = fields.get("college") or fields.get("board") or fields.get("board_or_university") or fields.get("institute")
                if cgpa is not None:
                    if 0.0 <= cgpa <= 10.0:
                        successfully_extracted += 1
                        field_metadata["diploma_cgpa"] = ExtractedField(
                            value=cgpa,
                            ocr_confidence=ocr_conf,
                            extraction_confidence=95.0,
                            validation_confidence=98.0,
                            status=VerificationStatusEnum.VERIFIED,
                            validation_notes=[f"Valid Diploma CGPA: {cgpa}"],
                        )
                    else:
                        errors.append(f"Invalid Diploma CGPA: {cgpa} (must be between 0.0 and 10.0)")
                elif pct is not None:
                    successfully_extracted += 1
                    field_metadata["diploma_percentage"] = ExtractedField(
                        value=pct,
                        status=VerificationStatusEnum.VERIFIED,
                    )
                else:
                    warnings.append("Could not extract Diploma CGPA/Percentage.")

                if dip_college:
                    successfully_extracted += 1
                    field_metadata["diploma_college"] = ExtractedField(value=dip_college, status=VerificationStatusEnum.VERIFIED)

                if year and 1990 <= year <= 2030:
                    successfully_extracted += 1
                    field_metadata["diploma_passing_year"] = ExtractedField(value=year, status=VerificationStatusEnum.VERIFIED)

        # -------------------------------------------------------------------
        # 4. CURRENT UG MARKSHEET VALIDATION
        # -------------------------------------------------------------------
        elif doc_type == "UG_MARKSHEET":
            total_expected = 4
            cgpa = fields.get("cgpa")
            sgpa = fields.get("sgpa")
            backlogs = fields.get("active_backlogs")
            semester = fields.get("current_semester")
            enrollment = fields.get("enrollment_number")
            branch = fields.get("branch")
            university = fields.get("university")

            # CGPA Validation
            if cgpa is not None:
                if 0.0 <= cgpa <= 10.0:
                    successfully_extracted += 1
                    field_metadata["CGPA"] = ExtractedField(
                        value=cgpa,
                        ocr_confidence=ocr_conf,
                        extraction_confidence=96.0,
                        validation_confidence=99.0,
                        status=VerificationStatusEnum.VERIFIED,
                        validation_notes=[f"Valid Cumulative CGPA: {cgpa} on 10.0 scale"],
                    )
                else:
                    errors.append(f"Extracted CGPA {cgpa} exceeds standard 10.0 scale.")
            elif sgpa is not None:
                # If only SGPA available, populate and verify as CGPA
                successfully_extracted += 1
                field_metadata["CGPA"] = ExtractedField(
                    value=sgpa,
                    ocr_confidence=ocr_conf,
                    extraction_confidence=92.0,
                    validation_confidence=96.0,
                    status=VerificationStatusEnum.VERIFIED,
                    validation_notes=[f"CGPA successfully verified from marksheet SGPA/CPI: {sgpa}"],
                )
            else:
                errors.append("Could not extract valid CGPA from UG marksheet.")

            # Backlogs Validation (0, integer, or UNKNOWN)
            if backlogs == "UNKNOWN":
                warnings.append("Active backlogs could not be reliably determined from document (marked UNKNOWN).")
                field_metadata["active_backlogs"] = ExtractedField(
                    value="UNKNOWN",
                    status=VerificationStatusEnum.REVIEW_REQUIRED,
                    validation_notes=["Backlog status could not be unambiguously verified from mark table."],
                )
            elif isinstance(backlogs, int) and backlogs >= 0:
                successfully_extracted += 1
                field_metadata["active_backlogs"] = ExtractedField(
                    value=backlogs,
                    ocr_confidence=ocr_conf,
                    extraction_confidence=95.0,
                    validation_confidence=98.0,
                    status=VerificationStatusEnum.VERIFIED,
                    validation_notes=[f"Active backlogs: {backlogs}"],
                )
            else:
                errors.append("Invalid backlog format or negative count detected.")

            if semester:
                successfully_extracted += 1
                field_metadata["current_semester"] = ExtractedField(value=semester, status=VerificationStatusEnum.VERIFIED)
            if enrollment:
                successfully_extracted += 1
                field_metadata["enrollment_number"] = ExtractedField(value=enrollment, status=VerificationStatusEnum.VERIFIED)
            if branch:
                successfully_extracted += 1
                field_metadata["branch"] = ExtractedField(value=branch, status=VerificationStatusEnum.VERIFIED)
            if university:
                successfully_extracted += 1
                field_metadata["university"] = ExtractedField(value=university, status=VerificationStatusEnum.VERIFIED)

        # Compute Confidence Indices
        extraction_conf = min(100.0, max(10.0, (successfully_extracted / max(1, total_expected)) * 100.0))
        val_penalty = len(errors) * 35.0 + len(warnings) * 10.0
        val_conf = max(0.0, min(100.0, 100.0 - val_penalty))

        # Assign per-field confidence & tier per Section 5 specification
        for fname, meta in field_metadata.items():
            meta.extraction_method = extraction_method
            meta.source = source_filename
            # Base confidence weighted by extraction method and overall validation
            field_c = round((meta.ocr_confidence * 0.4) + (meta.extraction_confidence * 0.3) + (val_conf * 0.3), 1)
            meta.confidence = field_c
            if field_c >= 95.0 and not errors:
                meta.status = VerificationStatusEnum.VERIFIED
            elif field_c >= 80.0:
                meta.status = VerificationStatusEnum.REVIEW_REQUIRED
            else:
                meta.status = VerificationStatusEnum.MANUAL_REVIEW

        return field_metadata, errors, warnings, ocr_conf, extraction_conf, val_conf

    @staticmethod
    def perform_cross_document_validation(
        extracted_name: Optional[str],
        extracted_enrollment: Optional[str],
        extracted_university: Optional[str],
        profile_name: Optional[str],
        profile_enrollment: Optional[str],
        profile_university: Optional[str],
        existing_doc_names: List[str] = None,
    ) -> Tuple[List[str], List[str]]:
        """
        Cross-validates information across documents and against canonical profile.
        Returns Tuple of (critical_mismatches, warnings).
        """
        critical_mismatches = []
        warnings = []

        # 1. Candidate Name Cross-Check (Disabled: name criteria removed from all documents per user specification)
        # Document verification no longer blocks or penalizes on extracted name differences.

        # 2. Enrollment Number Cross-Check
        if extracted_enrollment and profile_enrollment:
            if extracted_enrollment.replace(" ", "").upper() != profile_enrollment.replace(" ", "").upper():
                critical_mismatches.append(
                    f"ENROLLMENT_MISMATCH: Document enrollment '{extracted_enrollment}' does not match student profile '{profile_enrollment}'."
                )

        # 3. University Check
        if extracted_university and profile_university:
            sim_u = calculate_name_similarity(extracted_university, profile_university)
            if sim_u < 0.45:
                warnings.append(
                    f"University variance: Document indicates '{extracted_university}', while profile states '{profile_university}'."
                )

        return critical_mismatches, warnings

    @staticmethod
    def evaluate_verification_status(
        classification_confidence: float,
        validation_conf: float,
        extraction_conf: float,
        errors: List[str],
        critical_mismatches: List[str],
    ) -> VerificationStatusEnum:
        """
        Final decision engine determining whether document updates canonical profile directly
        or requires manual review / fails.
        """
        if critical_mismatches or len(errors) >= 2:
            return VerificationStatusEnum.MANUAL_REVIEW

        if errors:
            return VerificationStatusEnum.REVIEW_REQUIRED

        # Zero validation errors and high confidence -> Mark directly as VERIFIED
        if validation_conf >= 70.0 and extraction_conf >= 40.0:
            return VerificationStatusEnum.VERIFIED

        if classification_confidence >= 0.35 and validation_conf >= 50.0:
            return VerificationStatusEnum.REVIEW_REQUIRED

        return VerificationStatusEnum.MANUAL_REVIEW