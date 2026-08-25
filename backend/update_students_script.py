from app.database import get_sync_db

db = get_sync_db()

res = db.students.update_many(
    {},
    {
        "$set": {
            "has_resume": True,
            "resume_url": "/static/uploads/resume.pdf",
            "resume_filename": "resume.pdf"
        }
    }
)

print(f"Updated {res.modified_count} student documents in MongoDB database!")

# Also check document 1 full_name
doc1 = db.students.find_one({"full_name": {"$exists": False}})
if doc1:
    db.students.update_one({"_id": doc1["_id"]}, {"$set": {"full_name": "Aarav Sharma"}})
    print("Added missing full_name for document 1")

print("\nCurrent Student Documents in MongoDB:")
for s in db.students.find():
    print(s)
