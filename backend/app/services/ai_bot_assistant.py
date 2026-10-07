import re
import uuid
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional, Tuple

from app.database import chat_messages_collection, students_collection

logger = logging.getLogger("talentloq.ai_bot")

COMMON_DOMAINS = [
    "ai/ml",
    "deep learning",
    "machine learning",
    "data science",
    "data analyst",
    "computer vision",
    "nlp",
    "generative ai",
    "ai software development",
    "software development",
    "software engineer",
    "backend",
    "frontend",
    "full stack",
    "cloud",
    "devops",
    "cyber security",
    "mobile app development",
    "python",
    "java",
    "flutter",
    "react",
]


class AiBotAssistant:
    """
    Conversational AI Bot Assistant for student placement automation.
    Parses natural language instructions, updates criteria, and communicates
    application actions/reasons in human language.
    """

    @classmethod
    def parse_instruction(cls, text: str, student_doc: Dict[str, Any]) -> Dict[str, Any]:
        """
        Extracts domains, skills, salary range, and auto-apply intent from English text.
        Zero external LLM API cost — uses bounded regex and domain taxonomies.
        """
        clean_text = text.lower()

        # 1. Detect auto-apply intent
        has_apply_intent = any(kw in clean_text for kw in ["apply", "auto-apply", "auto apply", "submit application", "auto submit", "automatically apply"])
        is_negated = any(neg in clean_text for neg in ["don't apply", "do not apply", "stop applying", "pause", "disable auto", "only notify", "not apply", "never apply", "don't auto"])
        auto_apply = bool(has_apply_intent and not is_negated)

        # 2. Extract CTC / Salary Package Range
        min_ctc: float = 0.0
        max_ctc: Optional[float] = None

        # Matches "3-4 LPA", "3–4 LPA", "3 to 4.5 LPA", "3 - 5 LPA"
        range_match = re.search(r'(\d+(?:\.\d+)?)\s*(?:[-–—]|to)\s*(\d+(?:\.\d+)?)\s*(?:lpa|lakhs?|lac)?', clean_text)
        if range_match:
            min_ctc = float(range_match.group(1))
            max_ctc = float(range_match.group(2))
        else:
            # Matches "5+ LPA", "5 LPA", "minimum 5 LPA", "5 lpa+", "package of 5"
            single_match = re.search(r'(\d+(?:\.\d+)?)\s*(?:\+|plus)?\s*(?:lpa|lakhs?|lac)', clean_text)
            if single_match:
                min_ctc = float(single_match.group(1))
            else:
                pkg_match = re.search(r'(?:package|salary|ctc)\s*(?:of|at|around|min|minimum)?\s*(\d+(?:\.\d+)?)', clean_text)
                if pkg_match:
                    min_ctc = float(pkg_match.group(1))

        # 3. Extract Domains / Roles
        domain_pool = list(COMMON_DOMAINS)
        resume_skills = (student_doc.get("parsed_resume") or {}).get("skills") or []
        profile_skills = student_doc.get("skills") or []
        for s in set(resume_skills + profile_skills):
            if isinstance(s, str) and len(s) >= 2 and s.lower() not in domain_pool:
                domain_pool.append(s.lower())

        found_domains: List[str] = []
        for domain in domain_pool:
            # Use word boundary search
            if re.search(r'\b' + re.escape(domain) + r'\b', clean_text):
                if domain.lower() in ["ai/ml", "ai", "ml", "nlp"]:
                    formatted = "AI/ML" if domain.lower() in ["ai/ml", "ai", "ml"] else domain.upper()
                elif len(domain) <= 4:
                    formatted = domain.upper()
                else:
                    formatted = domain.title()
                found_domains.append(formatted)

        # Check if student references resume ("mentioned in my resume", "from my resume")
        if "resume" in clean_text or not found_domains:
            if profile_skills or resume_skills:
                all_skills = profile_skills + resume_skills
                found_domains.extend([s.title() for s in all_skills[:4] if isinstance(s, str)])

        if not found_domains:
            found_domains = ["AI/ML", "Software Development"]

        # Deduplicate
        seen = set()
        dedup_domains = []
        for d in found_domains:
            if d.lower() not in seen:
                seen.add(d.lower())
                dedup_domains.append(d)

        return {
            "target_roles": dedup_domains,
            "preferred_domains": dedup_domains[:3],
            "min_ctc_lpa": min_ctc,
            "max_ctc_lpa": max_ctc,
            "auto_apply_enabled": auto_apply,
            "raw_instruction": text,
        }

    @classmethod
    def generate_bot_reply(cls, parsed: Dict[str, Any], student_doc: Dict[str, Any]) -> str:
        """Generates natural conversational confirmation reply."""
        roles_str = ", ".join(parsed["target_roles"][:4])
        min_ctc = parsed["min_ctc_lpa"]
        max_ctc = parsed.get("max_ctc_lpa")

        if min_ctc > 0 and max_ctc:
            ctc_str = f"{min_ctc}–{max_ctc} LPA"
        elif min_ctc > 0:
            ctc_str = f"at least {min_ctc} LPA"
        else:
            ctc_str = "any salary package"

        if parsed["auto_apply_enabled"]:
            return (
                f"Understood! I am now actively monitoring newly published campus drives for you.\n\n"
                f"• Target Domains: {roles_str}\n"
                f"• Salary Range: {ctc_str}\n"
                f"• Mode: Autonomous Auto-Apply (Enabled)\n\n"
                f"Whenever a recruiter pushes a company, I will verify your eligibility against "
                f"university rules and automatically submit your application. I'll message you here with the details!"
            )
        else:
            return (
                f"Got it! I have paused automatic applications.\n\n"
                f"• Target Domains: {roles_str}\n"
                f"• Salary Range: {ctc_str}\n"
                f"• Mode: Advisory Mode (I will notify you here with 1-Tap apply recommendations instead of auto-applying)."
            )

    @classmethod
    async def process_student_message(cls, student_user_id: str, message_text: str, conversation_id: str) -> str:
        """Processes incoming student message to AI Bot, updates criteria, and persists response."""
        from app.database import drives_collection, users_collection

        student = await students_collection.find_one({
            "$or": [{"user_id": student_user_id}, {"student_id": student_user_id}],
        })
        if not student:
            user_doc = await users_collection.find_one({
                "$or": [{"user_id": student_user_id}]
            })
            student = {
                "user_id": student_user_id,
                "full_name": user_doc.get("full_name", "Student") if user_doc else "Student",
                "email": user_doc.get("email") if user_doc else None,
                "skills": [],
            }

        clean_text = message_text.lower().strip()
        first_name = (student.get("full_name") or "there").split()[0]

        # 1. Handle Greetings
        if clean_text in ["hello", "hi", "hey", "hello!", "hi!", "hey!", "help", "who are you", "who are you?"]:
            reply_text = (
                f"Hello {first_name}! 👋 I am your autonomous Placement Assistant.\n\n"
                "You can instruct me in natural conversational English, and I will automatically monitor "
                "recruiter drives, verify your eligibility and resume skills, and auto-apply for you.\n\n"
                "Try saying:\n"
                '• "Apply for upcoming companies that require AI/ML skills with a salary package of 3–4 LPA."\n'
                '• "Target Full Stack or Python roles with 5+ LPA."\n'
                '• "How many companies are there in AI/ML?"\n'
                '• "Pause auto applications."'
            )
        # 2. Handle queries about available companies / drives
        elif any(phrase in clean_text for phrase in ["how many companies", "which companies", "show companies", "list companies", "any companies", "companies having"]):
            cursor = drives_collection.find({"status": "published"}).limit(50)
            drives = await cursor.to_list(length=50)

            # Check matching keywords in user query (e.g. ai, ml, python, etc.)
            query_keywords = [k for k in ["ai", "ml", "ai/ml", "data science", "python", "software", "cloud", "backend"] if k in clean_text]
            if not query_keywords:
                query_keywords = ["ai", "ml", "software"]

            matching = []
            for d in drives:
                req_skills = [str(s).lower() for s in d.get("required_skills", [])]
                title = str(d.get("drive_title", "")).lower()
                desc = str(d.get("description", "")).lower()
                combined = f"{title} {' '.join(req_skills)} {desc}"
                if any(qk in combined for qk in query_keywords):
                    matching.append(d)

            if matching:
                lines = []
                for m in matching[:5]:
                    c_name = m.get("company_name", "Company")
                    d_title = m.get("drive_title", "Opportunity")
                    c_min = m.get("ctc_min")
                    ctc_info = f" ({c_min/100000:.1f} LPA)" if c_min and c_min > 50000 else ""
                    lines.append(f"• {c_name} — {d_title}{ctc_info}")

                reply_text = (
                    f"There are currently {len(matching)} active placement drive(s) matching your inquiry:\n\n"
                    + "\n".join(lines) +
                    "\n\nTo have me automatically apply for eligible opportunities like these, simply instruct me:\n"
                    f'"Apply for upcoming companies in {query_keywords[0].upper()} with your desired salary range."'
                )
            else:
                reply_text = (
                    "There are currently no active placement drives published in that specific domain. "
                    "However, if you give me your instructions (e.g., 'Apply for AI/ML roles with 3–4 LPA'), "
                    "I will continuously monitor newly published drives and automatically submit your application "
                    "the moment an eligible match is added!"
                )
        # 3. Handle criteria-view requests
        elif any(phrase in clean_text for phrase in [
            "my criteria", "view criteria", "show criteria", "what are my criteria", 
            "check criteria", "my preferences", "view preferences", "show preferences", 
            "current criteria", "current preferences", "what is my criteria", "what are my preferences"
        ]):
            from app.models import DEFAULT_CAREER_PREFERENCES
            stored = student.get("career_preferences") or DEFAULT_CAREER_PREFERENCES
            roles = stored.get("target_roles") or []
            domains = stored.get("preferred_domains") or []
            min_ctc = stored.get("min_ctc_lpa", 0.0)
            max_ctc = stored.get("max_ctc_lpa")
            auto_enabled = bool(stored.get("auto_apply_enabled", False))

            roles_str = ", ".join(roles) if roles else "None configured"
            domains_str = ", ".join(domains) if domains else "None configured"
            ctc_str = f"{min_ctc}–{max_ctc} LPA" if max_ctc else (f"{min_ctc}+ LPA" if min_ctc > 0 else "Any")
            mode_str = "Autonomous Auto-Apply Enabled" if auto_enabled else "Advisory Mode (Manual / Notify Only)"

            reply_text = (
                f"Here are your current placement criteria:\n\n"
                f"• Target Roles: {roles_str}\n"
                f"• Preferred Domains: {domains_str}\n"
                f"• Salary Range: {ctc_str}\n"
                f"• Mode: {mode_str}\n\n"
                "You can update these anytime by instructing me in plain English (e.g. 'Apply for Python roles with 6+ LPA')."
            )
        else:
            # 4. Standard criteria instruction
            parsed = cls.parse_instruction(message_text, student)

            # Update student profile with new persistent criteria using dotted $set keys
            now_iso = datetime.now(timezone.utc).isoformat()
            update_data: Dict[str, Any] = {
                "career_preferences.target_roles": parsed["target_roles"],
                "career_preferences.preferred_domains": parsed["preferred_domains"],
                "career_preferences.min_ctc_lpa": parsed["min_ctc_lpa"],
                "career_preferences.max_ctc_lpa": parsed.get("max_ctc_lpa"),
                "career_preferences.auto_apply_enabled": parsed["auto_apply_enabled"],
                "career_preferences.raw_instruction": parsed["raw_instruction"],
                "career_preferences.updated_at": now_iso,
            }

            # Re-embed vector
            from app.services.hybrid_matcher import get_text_embedding_async
            summary = f"Target Roles: {', '.join(parsed['target_roles'])}. Skills: {', '.join(student.get('skills', []))}"
            vec = await get_text_embedding_async(summary)
            if vec:
                update_data["preferences_vector"] = vec

            if student.get("_id"):
                await students_collection.update_one(
                    {"_id": student["_id"]},
                    {"$set": update_data},
                )

            reply_text = cls.generate_bot_reply(parsed, student)

            if parsed.get("auto_apply_enabled"):
                import asyncio
                from app.services.autonomous_placement_agent import autonomous_agent
                asyncio.create_task(autonomous_agent.process_student_for_all_drives(student_user_id))

        # Save AI Bot message in chat thread
        bot_msg = {
            "message_id": f"msg_{uuid.uuid4().hex[:12]}",
            "conversation_id": conversation_id,
            "sender_id": "ai_bot",
            "sender_name": "Placement Assistant",
            "recipient_id": student_user_id,
            "recipient_name": student.get("full_name", "Student"),
            "text": reply_text,
            "created_at": datetime.now(timezone.utc),
            "is_read": False,
        }
        await chat_messages_collection.insert_one(bot_msg)

        return reply_text

    @classmethod
    async def send_agent_notification_message(
        cls,
        student_user_id: str,
        text: str,
        company_name: str,
    ):
        """Sends an autonomous update directly into the student's AI Bot chat thread."""
        conv_id = f"conv_{student_user_id}_ai_bot"
        now = datetime.now(timezone.utc)

        msg_doc = {
            "message_id": f"msg_{uuid.uuid4().hex[:12]}",
            "conversation_id": conv_id,
            "sender_id": "ai_bot",
            "sender_name": "Placement Assistant",
            "recipient_id": student_user_id,
            "recipient_name": "Student",
            "text": text,
            "created_at": now,
            "is_read": False,
        }
        await chat_messages_collection.insert_one(msg_doc)


ai_bot_assistant = AiBotAssistant()
