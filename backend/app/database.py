import asyncio
import motor.motor_asyncio
from pymongo import MongoClient
from app.config import settings

# Async Motor Client for FastAPI Endpoints
async_client = motor.motor_asyncio.AsyncIOMotorClient(settings.MONGODB_URL)
async_db = async_client[settings.DATABASE_NAME]
grid_fs = motor.motor_asyncio.AsyncIOMotorGridFSBucket(async_db)

def get_grid_fs():
    try:
        loop = asyncio.get_running_loop()
        if async_client.get_io_loop() != loop:
            scoped = motor.motor_asyncio.AsyncIOMotorClient(settings.MONGODB_URL)
            return motor.motor_asyncio.AsyncIOMotorGridFSBucket(scoped[settings.DATABASE_NAME])
    except Exception:
        pass
    return motor.motor_asyncio.AsyncIOMotorGridFSBucket(async_db)

# Synchronous PyMongo Client for Scripts & Seed Tasks
sync_client = MongoClient(settings.MONGODB_URL)
sync_db = sync_client[settings.DATABASE_NAME]

# MongoDB Collections
users_collection = async_db["users"]
students_collection = async_db["students"]
audit_logs_collection = async_db["audit_logs"]
refresh_tokens_collection = async_db["refresh_tokens"]
otps_collection = async_db["otps"]
job_postings_collection = async_db["job_postings"]
company_listings_collection = async_db["company_listings"]
drives_collection = async_db["drives"]
applications_collection = async_db["applications"]
interviews_collection = async_db["interviews"]
announcements_collection = async_db["announcements"]
support_tickets_collection = async_db["support_tickets"]
notifications_collection = async_db["notifications"]
chat_messages_collection = async_db["chat_messages"]
verification_documents_collection = async_db["verification_documents"]
verification_audits_collection = async_db["verification_audits"]
ai_match_cache_collection = async_db["ai_match_cache"]

def get_ai_match_cache_collection():
    """Returns loop-resilient Motor collection for AI Match caching."""
    try:
        loop = asyncio.get_running_loop()
        if async_client.get_io_loop() != loop:
            scoped = motor.motor_asyncio.AsyncIOMotorClient(settings.MONGODB_URL)
            return scoped[settings.DATABASE_NAME]["ai_match_cache"]
    except Exception:
        pass
    return ai_match_cache_collection

async def init_db_indexes():
    """Configure MongoDB indexes for unique constraints, fast lookups, and TTL auto-deletion."""
    try:
        await users_collection.create_index("email", unique=True)
        await users_collection.create_index("user_id", unique=True)
        await students_collection.create_index("student_id", unique=True)
        await students_collection.create_index("user_id", unique=True)
        await audit_logs_collection.create_index("user_id")
        await audit_logs_collection.create_index("timestamp")
        await refresh_tokens_collection.create_index("token_id", unique=True)
        await refresh_tokens_collection.create_index("expires_at", expireAfterSeconds=0)
        await otps_collection.create_index("user_id")
        await otps_collection.create_index("expires_at", expireAfterSeconds=0)

        # Verification Collections Indexes
        await verification_documents_collection.create_index("document_id", unique=True)
        await verification_documents_collection.create_index("student_id")
        await verification_documents_collection.create_index("user_id")
        await verification_documents_collection.create_index("file_hash")
        await verification_documents_collection.create_index("document_type")
        await verification_audits_collection.create_index("audit_id", unique=True)
        await verification_audits_collection.create_index("student_id")
        await verification_audits_collection.create_index("timestamp")

        # Recruiter & Placement Indexes
        await job_postings_collection.create_index("job_id", unique=True)
        await job_postings_collection.create_index("status")
        await company_listings_collection.create_index("listing_id", unique=True)
        await company_listings_collection.create_index("posted_by")
        await company_listings_collection.create_index("status")
        await drives_collection.create_index("drive_id", unique=True)
        await drives_collection.create_index("posted_by")
        await drives_collection.create_index("status")
        await drives_collection.create_index("extracted_required_skills")
        await drives_collection.create_index("required_skills")
        await students_collection.create_index("skills")
        await applications_collection.create_index("app_id", unique=True)
        await applications_collection.create_index("job_id")
        await applications_collection.create_index("listing_id")
        await applications_collection.create_index("drive_id")
        await applications_collection.create_index("student_id")
        await applications_collection.create_index(
            [("student_id", 1), ("drive_id", 1)],
            unique=True,
            name="unique_student_drive_application",
            sparse=True,
        )
        await applications_collection.create_index("validation_status")
        await interviews_collection.create_index("interview_id", unique=True)
        await interviews_collection.create_index("student_id")
        await interviews_collection.create_index([("student_id", 1), ("status", 1)])
        await interviews_collection.create_index("status")
        await announcements_collection.create_index("announcement_id", unique=True)
        await announcements_collection.create_index("created_at")
        await support_tickets_collection.create_index("ticket_id", unique=True)
        await support_tickets_collection.create_index("student_id")
        await ai_match_cache_collection.create_index("cache_key", unique=True)
        await ai_match_cache_collection.create_index("created_at")

        # Notifications Indexes
        await notifications_collection.create_index([("recipient_id", 1), ("created_at", -1)])
        await notifications_collection.create_index([("user_id", 1), ("created_at", -1)])

        # Verification Documents Compound Indexes
        await verification_documents_collection.create_index([("user_id", 1), ("target_type", 1)])
        await verification_documents_collection.create_index([("student_id", 1), ("target_type", 1)])

        # Chat Messages Indexes
        await chat_messages_collection.create_index([("conversation_id", 1), ("created_at", 1)])
        await chat_messages_collection.create_index("sender_id")
        await chat_messages_collection.create_index("recipient_id")
    except (asyncio.CancelledError, KeyboardInterrupt):
        pass
    except Exception:
        pass

def get_sync_db():
    return sync_db
