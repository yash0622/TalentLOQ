"""
TalentLOQ — Automatic Drive & Company Seeder with Official PDF Brochure Generation.
Reads 'Synthetic_Company_Internship_Data_1000.xlsx', generates an authentic, branded
1-page Job Description & Brochure PDF for each company using PyMuPDF, uploads to MongoDB GridFS,
and inserts all 1,000 drives into 'drives' and 'company_listings' collections.
"""

import os
import re
import uuid
import fitz  # PyMuPDF
import pandas as pd
from datetime import datetime, timezone, timedelta
import sys
from pathlib import Path
from typing import Dict, Any, List, Tuple
from gridfs import GridFS

# Ensure backend root is on sys.path
BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.database import sync_db
from app.config import settings

EXCEL_PATH = r"C:\Users\sharm\OneDrive\Desktop\Synthetic_Company_Internship_Data_1000.xlsx"
STATIC_UPLOADS_DIR = Path(__file__).resolve().parent.parent / "static" / "uploads"
STATIC_UPLOADS_DIR.mkdir(parents=True, exist_ok=True)


def parse_ctc(ctc_raw: Any, stipend_raw: Any) -> Tuple[float, float, float]:
    """Parses CTC and Stipend into numeric min, max, and monthly stipend values."""
    ctc_min, ctc_max, stipend_val = 0.0, 0.0, 0.0

    if pd.notna(stipend_raw):
        nums = re.findall(r'[\d,]+', str(stipend_raw))
        if nums:
            try:
                stipend_val = float(nums[0].replace(',', ''))
            except Exception:
                pass

    if pd.notna(ctc_raw):
        nums = re.findall(r'[\d,]+', str(ctc_raw))
        if len(nums) >= 2:
            try:
                v1 = float(nums[0].replace(',', '')) / 100000.0
                v2 = float(nums[1].replace(',', '')) / 100000.0
                ctc_min, ctc_max = round(min(v1, v2), 2), round(max(v1, v2), 2)
            except Exception:
                pass
        elif len(nums) == 1:
            try:
                v = float(nums[0].replace(',', '')) / 100000.0
                ctc_min, ctc_max = round(v, 2), round(v * 1.5, 2)
            except Exception:
                pass

    if ctc_min == 0.0 and ctc_max == 0.0:
        if stipend_val > 0:
            ctc_min = round((stipend_val * 12) / 100000.0, 2)
            ctc_max = round(ctc_min * 1.2, 2)
        else:
            ctc_min, ctc_max = 5.0, 9.0

    return ctc_min, ctc_max, stipend_val


def parse_cgpa(eligibility_raw: Any) -> float:
    """Extracts minimum CGPA cutoff from eligibility criteria text."""
    if pd.isna(eligibility_raw):
        return 6.0
    text = str(eligibility_raw)
    m_pct = re.search(r'(\d{2})%', text)
    if m_pct:
        pct = float(m_pct.group(1))
        return round(pct / 10.0, 1)  # 65% -> 6.5 CGPA
    m_cgpa = re.search(r'(\d\.\d)', text)
    if m_cgpa:
        return float(m_cgpa.group(1))
    return 6.0


def parse_courses(courses_raw: Any) -> List[str]:
    """Cleans course list into standard course tokens."""
    if pd.isna(courses_raw):
        return ["BTECH_CSE", "BCA", "ALL"]
    text = str(courses_raw)
    tokens = set()
    if "Computer Science" in text or "B.Tech" in text:
        tokens.add("BTECH_CSE")
    if "B.C.A" in text or "BCA" in text or "Computer Applications" in text:
        tokens.add("BCA")
    if "Information Technology" in text:
        tokens.add("BTECH_IT")
    if "B.Sc" in text:
        tokens.add("BSC_CS")
    if "M.Tech" in text:
        tokens.add("MTECH_CSE")
    if not tokens:
        tokens.add("ALL")
    return sorted(list(tokens))


def parse_skills(desc_raw: Any, elig_raw: Any) -> List[str]:
    """Extracts technical skills keywords from description and eligibility criteria."""
    combined = f"{desc_raw} {elig_raw}".lower()
    skill_keywords = [
        "Python", "SQL", "Excel", "FastAPI", "Machine Learning", "Data Analytics",
        "React", "Node.js", "Java", "Docker", "AWS", "Dashboards", "Statistics",
        "Data Visualization", "Problem Solving", "Flutter", "Git", "C++", "JavaScript",
        "Cybersecurity", "Deep Learning", "TensorFlow", "Pandas", "NumPy"
    ]
    found = [k for k in skill_keywords if k.lower() in combined]
    return found if found else ["Problem Solving", "Technical Aptitude", "Communication Skills"]


def generate_company_pdf(data: Dict[str, Any]) -> bytes:
    """Generates a professional 1-page PDF document brochure for the drive using PyMuPDF."""
    doc = fitz.open()
    page = doc.new_page(width=595, height=842)  # A4

    # Palette
    c_navy = (0.08, 0.18, 0.36)       # Primary header navy
    c_light_bg = (0.95, 0.97, 1.0)    # Soft card background
    c_gray_border = (0.82, 0.86, 0.92)# Card border
    c_text_dark = (0.12, 0.15, 0.20)  # Primary text
    c_text_muted = (0.40, 0.45, 0.52) # Secondary text
    c_accent_green = (0.10, 0.55, 0.30)# CTC / Stipend highlight

    # 1. Top Header Banner
    header_rect = fitz.Rect(0, 0, 595, 75)
    page.draw_rect(header_rect, color=c_navy, fill=c_navy)
    page.insert_text((35, 32), "GSFC UNIVERSITY — CAMPUS RECRUITMENT SPECIFICATION",
                     fontname="helv", fontsize=13, color=(1, 1, 1))
    page.insert_text((35, 52), "TalentLOQ Placement Intelligence Platform  •  Official Job Description & Brochure",
                     fontname="helv", fontsize=9, color=(0.85, 0.92, 1.0))

    # 2. Company & Role Card
    card_rect = fitz.Rect(35, 90, 560, 195)
    page.draw_rect(card_rect, color=c_gray_border, fill=c_light_bg, width=1.0)

    comp_name = str(data.get("company_name", "Corporate Partner"))
    role_title = str(data.get("drive_title", "Position"))
    loc = str(data.get("location", "Campus"))
    emp_type = str(data.get("employment_type", "Full-Time")).title()
    industry = str(data.get("industry", "Technology"))
    ctc_text = f"CTC: INR {data.get('ctc_min', 6.0)} - {data.get('ctc_max', 12.0)} LPA"
    if data.get("stipend") and float(data.get("stipend")) > 0:
        ctc_text += f"  |  Stipend: INR {int(data['stipend']):,}/mo"

    page.insert_text((50, 118), comp_name, fontname="helv", fontsize=17, color=c_navy)
    page.insert_text((50, 138), f"{role_title}  ({emp_type})", fontname="helv", fontsize=12, color=c_text_dark)
    page.insert_text((50, 156), f"Location: {loc}   •   Industry: {industry}   •   Duration: {data.get('duration', 'Full-Time')}",
                     fontname="helv", fontsize=9.5, color=c_text_muted)

    # CTC Pill Box
    pill_rect = fitz.Rect(50, 166, 545, 187)
    page.draw_rect(pill_rect, color=c_accent_green, fill=(0.90, 0.98, 0.92), width=0.8)
    page.insert_text((58, 180), f"✔ {ctc_text}   •   Bond: {data.get('bond', 'No Bond Required')}",
                     fontname="helv", fontsize=9, color=c_accent_green)

    # 3. Section: Academic Eligibility & Criteria
    y = 215
    page.insert_text((35, y), "ACADEMIC ELIGIBILITY & POLICIES", fontname="helv", fontsize=11, color=c_navy)
    page.draw_line((35, y + 4), (560, y + 4), color=c_navy, width=1)
    y += 18

    min_cgpa = data.get("min_cgpa", 6.0)
    courses_str = ", ".join(data.get("eligible_courses", ["BTECH_CSE", "BCA"]))
    elig_clean = str(data.get("eligibility_raw", "Minimum 60% aggregate. Positive attitude and problem-solving ability.")).replace("\x95", "• ").replace("\u2022", "• ").replace("\n", " ").strip()
    if len(elig_clean) > 280:
        elig_clean = elig_clean[:277] + "..."

    page.insert_text((35, y), f"• Minimum CGPA Cutoff: {min_cgpa}   •   Campus / School: {data.get('school_tag', 'School of Technology')}",
                     fontname="helv", fontsize=9.5, color=c_text_dark)
    y += 15
    page.insert_text((35, y), f"• Eligible Academic Programs: {courses_str}",
                     fontname="helv", fontsize=9.5, color=c_text_dark)
    y += 15
    page.insert_textbox(fitz.Rect(35, y, 560, y + 36), f"• Summary: {elig_clean}",
                        fontname="helv", fontsize=9, color=c_text_muted)
    y += 42

    # 4. Section: Job Description & Responsibilities
    page.insert_text((35, y), "JOB DESCRIPTION & KEY RESPONSIBILITIES", fontname="helv", fontsize=11, color=c_navy)
    page.draw_line((35, y + 4), (560, y + 4), color=c_navy, width=1)
    y += 18

    desc_clean = str(data.get("description", "")).replace("\x95", "• ").replace("\u2022", "• ").strip()
    lines = [l.strip() for l in desc_clean.split("\n") if l.strip()]
    if lines:
        for l in lines[:5]:
            l_text = l if l.startswith("•") else f"• {l}"
            page.insert_text((35, y), l_text[:110], fontname="helv", fontsize=9, color=c_text_dark)
            y += 14
    else:
        page.insert_text((35, y), "• Work on technical development assignments aligned with corporate business goals.",
                         fontname="helv", fontsize=9, color=c_text_dark)
        y += 14

    y += 8

    # 5. Section: Required Skills
    page.insert_text((35, y), "REQUIRED TECHNICAL SKILLS", fontname="helv", fontsize=11, color=c_navy)
    page.draw_line((35, y + 4), (560, y + 4), color=c_navy, width=1)
    y += 18
    skills_str = "   |   ".join(data.get("required_skills", []))
    page.insert_text((35, y), f"Skills Evaluated: {skills_str}", fontname="helv", fontsize=9.5, color=c_text_dark)
    y += 24

    # 6. Section: About the Organisation & Culture
    page.insert_text((35, y), "ABOUT THE ORGANISATION & WORK CULTURE", fontname="helv", fontsize=11, color=c_navy)
    page.draw_line((35, y + 4), (560, y + 4), color=c_navy, width=1)
    y += 18

    about_clean = str(data.get("about", "")).replace("\x95", "• ").replace("\u2022", "• ").replace("\n", " ").strip()
    if len(about_clean) > 250:
        about_clean = about_clean[:247] + "..."
    page.insert_textbox(fitz.Rect(35, y, 560, y + 36), about_clean, fontname="helv", fontsize=9, color=c_text_dark)
    y += 40

    why_clean = str(data.get("why_join", "")).replace("\x95", "• ").replace("\u2022", "• ").replace("\n", "  •  ").strip()
    if len(why_clean) > 200:
        why_clean = why_clean[:197] + "..."
    page.insert_text((35, y), f"Perks & Benefits: {why_clean}", fontname="helv", fontsize=8.5, color=c_text_muted)
    y += 16
    page.insert_text((35, y), f"Official Website: {data.get('website', 'www.company.in')}   •   Headcount: {data.get('size', '51-200 Employees')}",
                     fontname="helv", fontsize=8.5, color=c_navy)

    # 7. Bottom Footer
    page.draw_line((35, 805), (560, 805), color=c_gray_border, width=0.8)
    page.insert_text((35, 822),
                     "TalentLOQ Verified Campus Placement Specification  •  Protected Document  •  GSFC University",
                     fontname="helv", fontsize=8, color=c_text_muted)

    pdf_bytes = doc.tobytes()
    doc.close()
    return pdf_bytes


def seed_drives_from_excel():
    """Main execution: reads excel, creates PDFs, uploads to GridFS, and seeds drives."""
    print("=" * 70)
    print("TALENTLOQ DRIVE & PDF BROCHURE SEEDER ENGINE")
    print("=" * 70)

    if not os.path.exists(EXCEL_PATH):
        print(f"ERROR: Excel file not found at: {EXCEL_PATH}")
        return

    print(f"Reading Excel: {EXCEL_PATH}...")
    df = pd.read_excel(EXCEL_PATH)
    print(f"Loaded {len(df)} company listings from Excel.")

    gfs = GridFS(sync_db)
    drives_col = sync_db["drives"]
    company_listings_col = sync_db["company_listings"]

    # Clear existing synthetic SOT drives to keep collection fresh and clean
    deleted_cnt = drives_col.delete_many({"school_tag": "SOT - School of Technology"}).deleted_count
    company_listings_col.delete_many({"school_tag": "SOT - School of Technology"})
    print(f"Cleaned {deleted_cnt} previous drives in 'SOT - School of Technology'.")

    now = datetime.now(timezone.utc)
    drives_to_insert = []
    listings_to_insert = []

    print(f"Generating branded PDFs & inserting drives into MongoDB GridFS...")

    for idx, row in df.iterrows():
        drive_id = f"drv-{uuid.uuid4().hex[:12]}"
        company_name = str(row.get("Company Name", "Partner Firm")).strip()
        role = str(row.get("Position / Role", "Software Engineer")).strip()
        location = str(row.get("Location", "Vadodara / Remote")).strip()
        emp_type_raw = str(row.get("Employment Type", "full_time")).strip().lower()
        emp_type = "internship" if "intern" in emp_type_raw else "full_time"
        industry = str(row.get("Industry", "Information Technology")).strip()
        desc = str(row.get("Job Description", ""))
        elig_raw = str(row.get("Eligibility Criteria", ""))
        courses_raw = row.get("Eligible Courses")
        why_join = str(row.get("Why Join Us", ""))
        about_org = str(row.get("About The Organisation", ""))
        website = str(row.get("Website", f"www.{re.sub(r'[^a-zA-Z0-9]', '', company_name).lower()}.com"))
        org_size = str(row.get("Organisation Size", "50-200"))
        duration = str(row.get("Internship Duration", "Full-Time" if emp_type == "full_time" else "3 Months"))
        bond = str(row.get("Bond", "No Bond Required"))

        ctc_min, ctc_max, stipend_val = parse_ctc(row.get("CTC (Per Annum)"), row.get("Stipend (Per Month)"))
        min_cgpa = parse_cgpa(elig_raw)
        eligible_courses = parse_courses(courses_raw)
        skills = parse_skills(desc, elig_raw)

        # Policy flags from Excel
        has_access = str(row.get("Has Placement Access", "Yes")).strip().lower() in ["yes", "true", "1"]
        is_eligible = str(row.get("Eligible For Placements", "Yes")).strip().lower() in ["yes", "true", "1"]
        int_jobs = str(row.get("Interested In Jobs", "Yes")).strip().lower() in ["yes", "true", "1"]
        int_intern = str(row.get("Interested In Internships", "Yes")).strip().lower() in ["yes", "true", "1"]

        # Generate custom PDF
        pdf_data = {
            "company_name": company_name,
            "drive_title": role,
            "location": location,
            "employment_type": emp_type,
            "industry": industry,
            "ctc_min": ctc_min,
            "ctc_max": ctc_max,
            "stipend": stipend_val,
            "min_cgpa": min_cgpa,
            "eligible_courses": eligible_courses,
            "eligibility_raw": elig_raw,
            "description": desc,
            "required_skills": skills,
            "about": about_org,
            "why_join": why_join,
            "website": website,
            "size": org_size,
            "duration": duration,
            "bond": bond,
            "school_tag": "SOT - School of Technology",
        }
        pdf_bytes = generate_company_pdf(pdf_data)

        # Save to local disk for fast file access fallback
        pdf_filename = f"{drive_id}.pdf"
        local_file_path = STATIC_UPLOADS_DIR / pdf_filename
        with open(local_file_path, "wb") as f:
            f.write(pdf_bytes)

        # Upload to GridFS
        grid_file_id = gfs.put(
            pdf_bytes,
            filename=pdf_filename,
            contentType="application/pdf",
            metadata={
                "drive_id": drive_id,
                "company_name": company_name,
                "role": role,
                "generated_by": "TalentLOQ_Seeder",
                "is_public": True,
                "content_type": "application/pdf",
            }
        )

        pdf_url = f"/api/v1/files/{str(grid_file_id)}"

        drive_doc = {
            "drive_id": drive_id,
            "company_name": company_name,
            "company_email": f"careers@{re.sub(r'[^a-zA-Z0-9]', '', company_name).lower()[:15]}.com",
            "drive_title": role,
            "mode": "on_campus",
            "employment_type": emp_type,
            "location": location,
            "school_tag": "SOT - School of Technology",
            "ctc_min": ctc_min,
            "ctc_max": ctc_max,
            "stipend": stipend_val,
            "description": desc.replace("\x95", "• ").replace("\u2022", "• ").strip(),
            "key_responsibilities": [desc[:150]],
            "required_skills": skills,
            "extracted_required_skills": skills,
            "preferred_skills": skills[:2],
            "qualifications": "B.Tech / BCA",
            "additional_requirements": why_join,
            "bond_details": bond if bond and bond != "nan" else "No Bond",
            "attachment_pdf_url": pdf_url,
            "pdf_url": pdf_url,
            "grid_file_id": str(grid_file_id),
            "eligible_courses": eligible_courses,
            "eligibility_criteria_summary": f"Min CGPA {min_cgpa} in SOT",
            "placement_policy_flags": {
                "requires_placement_access": has_access,
                "requires_placement_eligible": is_eligible,
                "requires_job_interest": int_jobs,
                "requires_internship_interest": int_intern,
            },
            "min_cgpa": min_cgpa,
            "status": "published",  # Set to published so students see them live!
            "posted_by": "recruiter_admin_system",
            "created_at": now - timedelta(days=idx % 30),
            "updated_at": now,
        }

        # Also populate company_listings for legacy fallback compatibility
        listing_doc = {
            "listing_id": drive_id,
            "company_name": company_name,
            "company_email": drive_doc["company_email"],
            "description": drive_doc["description"],
            "pdf_url": pdf_url,
            "interview_job": role,
            "bond_time": drive_doc["bond_details"],
            "interview_datetime": (now + timedelta(days=7 + (idx % 14))).strftime("%Y-%m-%d %H:%M"),
            "interview_venue": f"SOT Auditorium, Room {101 + (idx % 20)}",
            "cgpa_criteria": min_cgpa,
            "school_tag": "SOT - School of Technology",
            "status": "published",
            "posted_by": "recruiter_admin_system",
            "created_at": now,
            "updated_at": now,
        }

        drives_to_insert.append(drive_doc)
        listings_to_insert.append(listing_doc)

        if (idx + 1) % 100 == 0 or idx == len(df) - 1:
            print(f"Processed {idx + 1}/{len(df)} drives and PDFs...")

    # Bulk insert
    if drives_to_insert:
        drives_col.insert_many(drives_to_insert)
        company_listings_col.insert_many(listings_to_insert)

    print("=" * 70)
    print(f"SUCCESS! Successfully seeded {len(drives_to_insert)} drives into MongoDB!")
    print(f"Generated & stored {len(drives_to_insert)} customized PDF brochures in GridFS.")
    print(f"Saved local static copies into: {STATIC_UPLOADS_DIR}")
    print("=" * 70)


if __name__ == "__main__":
    seed_drives_from_excel()
