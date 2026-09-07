"""
Seeds sample campus placement drives into the MongoDB drives collection for development/demo.
"""
import uuid
from datetime import datetime, timezone
from app.database import sync_db

def seed_drives():
    drives_col = sync_db["drives"]
    sample_drives = [
        {
            "drive_id": str(uuid.uuid4()),
            "company_name": "Google",
            "drive_title": "Associate Software Engineer",
            "employment_type": "full_time",
            "ctc_min": 18.0,
            "ctc_max": 28.0,
            "min_cgpa": 7.5,
            "eligible_courses": ["all"],
            "status": "published",
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
        {
            "drive_id": str(uuid.uuid4()),
            "company_name": "Microsoft",
            "drive_title": "Cloud Solutions Developer",
            "employment_type": "full_time",
            "ctc_min": 14.0,
            "ctc_max": 24.0,
            "min_cgpa": 7.0,
            "eligible_courses": ["all"],
            "status": "published",
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
        {
            "drive_id": str(uuid.uuid4()),
            "company_name": "Tata Consultancy Services",
            "drive_title": "Digital Technology Specialist",
            "employment_type": "full_time",
            "ctc_min": 7.5,
            "ctc_max": 11.5,
            "min_cgpa": 6.0,
            "eligible_courses": ["all"],
            "status": "published",
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
        {
            "drive_id": str(uuid.uuid4()),
            "company_name": "Larsen & Toubro (L&T)",
            "drive_title": "Graduate Engineer Trainee",
            "employment_type": "full_time",
            "ctc_min": 6.5,
            "ctc_max": 9.0,
            "min_cgpa": 6.0,
            "eligible_courses": ["all"],
            "status": "published",
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
    ]

    for d in sample_drives:
        existing = drives_col.find_one({"company_name": d["company_name"], "drive_title": d["drive_title"]})
        if not existing:
            drives_col.insert_one(d)
            print(f"Inserted: {d['company_name']} - {d['drive_title']}")
        else:
            print(f"Already exists: {d['company_name']}")

if __name__ == "__main__":
    seed_drives()
