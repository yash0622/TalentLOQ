import gridfs
from app.database import get_sync_db

db = get_sync_db()
fs = gridfs.GridFS(db)

# Upload sample PDF into MongoDB GridFS
pdf_content = b"%PDF-1.4 sample pdf content for GridFS in MongoDB Compass"

file_id = fs.put(
    pdf_content,
    filename="student_resume_gridfs.pdf",
    content_type="application/pdf",
    uploader="talentloq_system"
)

print(f"Uploaded file to MongoDB GridFS successfully! File ID: {file_id}")
print("Collections created in MongoDB database:")
print(" - fs.files")
print(" - fs.chunks")
