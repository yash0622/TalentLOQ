import asyncio
import logging
import motor.motor_asyncio
from pymongo import MongoClient
from app.config import settings

logger = logging.getLogger("talentloq.database")

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

# Synchronous PyMongo Client for Scripts & Seed Tasks (Lazily Loaded)
_sync_client = None
_sync_db = None

def get_sync_client():
    global _sync_client
    if _sync_client is None:
        _sync_client = MongoClient(settings.MONGODB_URL)
    return _sync_client

def get_sync_db():
    global _sync_db
    if _sync_db is None:
        _sync_db = get_sync_client()[settings.DATABASE_NAME]
    return _sync_db

class _LazySyncClientProxy:
    def __getattr__(self, name):
        return getattr(get_sync_client(), name)
    def __getitem__(self, name):
        return get_sync_client()[name]

class _LazySyncDbProxy:
    def __getattr__(self, name):
        return getattr(get_sync_db(), name)
    def __getitem__(self, name):
        return get_sync_db()[name]

sync_client = _LazySyncClientProxy()
sync_db = _LazySyncDbProxy()

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
agent_runs_collection = async_db["agent_runs"]
device_tokens_collection = async_db["device_tokens"]
notification_preferences_collection = async_db["notification_preferences"]

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

def get_agent_runs_collection():
    """Returns loop-resilient Motor collection for agent_runs."""
    try:
        loop = asyncio.get_running_loop()
        if async_client.get_io_loop() != loop:
            scoped = motor.motor_asyncio.AsyncIOMotorClient(settings.MONGODB_URL)
            return scoped[settings.DATABASE_NAME]["agent_runs"]
    except Exception:
        pass
    return agent_runs_collection

async def init_db_indexes():
    """Configure MongoDB indexes for unique constraints, fast lookups, and TTL auto-deletion."""
    try:
        coros = [
            users_collection.create_index("email", unique=True),
            users_collection.create_index("user_id", unique=True),
            students_collection.create_index("student_id", unique=True),
            students_collection.create_index("user_id", unique=True),
            audit_logs_collection.create_index("user_id"),
            audit_logs_collection.create_index("timestamp"),
            refresh_tokens_collection.create_index("token_id", unique=True),
            refresh_tokens_collection.create_index("expires_at", expireAfterSeconds=0),
            otps_collection.create_index("user_id"),
            otps_collection.create_index("expires_at", expireAfterSeconds=0),
            verification_documents_collection.create_index("document_id", unique=True),
            verification_documents_collection.create_index("student_id"),
            verification_documents_collection.create_index("user_id"),
            verification_documents_collection.create_index("file_hash"),
            verification_documents_collection.create_index("document_type"),
            verification_audits_collection.create_index("audit_id", unique=True),
            verification_audits_collection.create_index("student_id"),
            verification_audits_collection.create_index("timestamp"),
            job_postings_collection.create_index("job_id", unique=True),
            job_postings_collection.create_index("status"),
            company_listings_collection.create_index("listing_id", unique=True),
            company_listings_collection.create_index("posted_by"),
            company_listings_collection.create_index("status"),
            drives_collection.create_index("drive_id", unique=True),
            drives_collection.create_index("posted_by"),
            drives_collection.create_index("status"),
            drives_collection.create_index("extracted_required_skills"),
            drives_collection.create_index("required_skills"),
            students_collection.create_index("skills"),
            students_collection.create_index([("cgpa", -1), ("skills", 1)]),
            students_collection.create_index([("cgpa", -1)]),
            students_collection.create_index("full_name_lower"),
            students_collection.create_index("active_backlogs"),
            applications_collection.create_index("app_id", unique=True),
            applications_collection.create_index("job_id"),
            applications_collection.create_index("listing_id"),
            applications_collection.create_index("drive_id"),
            applications_collection.create_index("student_id"),
            applications_collection.create_index(
                [("student_id", 1), ("drive_id", 1)],
                unique=True,
                name="unique_student_drive_application",
                sparse=True,
            ),
            applications_collection.create_index("validation_status"),
            interviews_collection.create_index("interview_id", unique=True),
            interviews_collection.create_index("student_id"),
            interviews_collection.create_index([("student_id", 1), ("status", 1)]),
            interviews_collection.create_index("status"),
            announcements_collection.create_index("announcement_id", unique=True),
            announcements_collection.create_index("created_at"),
            support_tickets_collection.create_index("ticket_id", unique=True),
            support_tickets_collection.create_index("student_id"),
            ai_match_cache_collection.create_index("cache_key", unique=True),
            ai_match_cache_collection.create_index("created_at"),
            notifications_collection.create_index([("recipient_id", 1), ("created_at", -1)]),
            notifications_collection.create_index([("user_id", 1), ("created_at", -1)]),
            verification_documents_collection.create_index([("user_id", 1), ("target_type", 1)]),
            verification_documents_collection.create_index([("student_id", 1), ("target_type", 1)]),
            chat_messages_collection.create_index([("conversation_id", 1), ("created_at", 1)]),
            chat_messages_collection.create_index([("conversation_id", 1), ("created_at", -1)]),
            chat_messages_collection.create_index("sender_id"),
            chat_messages_collection.create_index("recipient_id"),
            device_tokens_collection.create_index("token", unique=True),
            device_tokens_collection.create_index("user_id"),
            notification_preferences_collection.create_index("user_id", unique=True),
        ]
        await asyncio.gather(*coros, return_exceptions=True)
    except (asyncio.CancelledError, KeyboardInterrupt):
        pass
    except Exception as e:
        logger.warning(f"Failed to initialize database indexes: {e}")

