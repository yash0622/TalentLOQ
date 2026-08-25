#!/usr/bin/env python3
"""
One-Time Admin Seed Script for Talentloq
Inserts the single reserved recruiter account into the MongoDB 'users' collection.
NOTE: This script is for internal/admin execution ONLY and is NOT exposed as a public API endpoint.
"""

import sys
import os
import uuid
from datetime import datetime, timezone

# Ensure project root directory is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.config import settings
from app.security import hash_password
from pymongo import MongoClient

def seed_recruiter():
    print("=" * 60)
    print("Talentloq - Recruiter Account Admin Seed Script")
    print("=" * 60)

    recruiter_email = settings.RECRUITER_EMAIL.lower()
    initial_password = settings.RECRUITER_INITIAL_PASSWORD

    print(f"Target Recruiter Email: {recruiter_email}")
    print(f"MongoDB Target URI:     {settings.MONGODB_URL}")
    print(f"Database Name:          {settings.DATABASE_NAME}")

    try:
        client = MongoClient(settings.MONGODB_URL, serverSelectionTimeoutMS=5000)
        db = client[settings.DATABASE_NAME]
        users_col = db["users"]

        # Check if recruiter account already exists
        existing = users_col.find_one({"email": recruiter_email})
        if existing:
            print(f"\n[INFO] Recruiter account '{recruiter_email}' already exists in database.")
            print(f"       User ID: {existing.get('user_id')}")
            print(f"       Role:    {existing.get('role')}")
            print(f"       Status:  is_verified={existing.get('is_verified')}, must_change_password={existing.get('must_change_password')}")
            return existing

        # Build Recruiter User Document
        recruiter_doc = {
            "user_id": str(uuid.uuid4()),
            "email": recruiter_email,
            "password_hash": hash_password(initial_password),
            "role": "recruiter",
            "created_at": datetime.now(timezone.utc),
            "is_verified": True,
            "trusted_devices": [],
            "must_change_password": True
        }

        result = users_col.insert_one(recruiter_doc)
        print(f"\n[SUCCESS] Seeded recruiter account successfully!")
        print(f"          Inserted MongoDB _id: {result.inserted_id}")
        print(f"          User ID:              {recruiter_doc['user_id']}")
        print(f"          Role:                 {recruiter_doc['role']}")
        print(f"          Is Verified:          {recruiter_doc['is_verified']}")
        print(f"          Must Change Password: {recruiter_doc['must_change_password']}")
        print(f"\n[ACTION REQUIRED] Initial Password set to: {initial_password}")
        print("                  The recruiter MUST change password on first login.")
        return recruiter_doc

    except Exception as e:
        print(f"\n[ERROR] Failed to seed recruiter account: {e}")
        sys.exit(1)

if __name__ == "__main__":
    seed_recruiter()
