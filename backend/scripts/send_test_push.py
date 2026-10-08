#!/usr/bin/env python3
"""
CLI Script to dispatch a live test push notification via TalentLOQ backend.
Usage:
    python scripts/send_test_push.py --user-id student-123 --title "Drive Alert" --body "Google drive opened!"
"""
import sys
import os
import asyncio
import argparse

# Add backend directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.firebase_manager import init_firebase
from app.services.push_notification_service import notify


async def main():
    parser = argparse.ArgumentParser(description="Send test push notification to a TalentLOQ user")
    parser.add_argument("--user-id", required=True, help="Target user ID or student ID")
    parser.add_argument("--title", default="TalentLOQ Test Push", help="Notification title")
    parser.add_argument("--body", default="This is a test notification from TalentLOQ CLI.", help="Notification body")
    parser.add_argument("--type", default="test_push", help="Notification type category")
    parser.add_argument("--entity-id", default="cli_test", help="Entity ID for deep-linking")

    args = parser.parse_args()

    print(f"Initializing Firebase...")
    init_firebase()

    print(f"Sending test notification to user '{args.user_id}'...")
    res = await notify(
        user_ids=[args.user_id],
        type=args.type,
        title=args.title,
        body=args.body,
        data={"type": args.type, "entity_id": args.entity_id},
    )

    print(f"Result: {res}")


if __name__ == "__main__":
    asyncio.run(main())
