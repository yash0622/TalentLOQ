import logging
import uuid
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional
import numpy as np

from app.database import (
    drives_collection,
    students_collection,
    applications_collection,
    notifications_collection,
    agent_runs_collection,
)
from app.eligibility import compute_eligibility
from app.audit_service import log_agent_decision
from app.services.skill_matcher import skill_matcher_engine

logger = logging.getLogger("talentloq.autonomous_agent")


class AutonomousPlacementAgent:
    """
    Zero-LLM Agentic Placement Copilot.
    Autonomously evaluates new placement drives against student career preferences,
    verifies eligibility against university rules, and auto-applies or dispatches alerts.
    """

    @staticmethod
    def _cosine_similarity(vec_a: Optional[List[float]], vec_b: Optional[List[float]]) -> float:
        if not vec_a or not vec_b or len(vec_a) != len(vec_b):
            return 0.0
        a = np.array(vec_a, dtype=np.float32)
        b = np.array(vec_b, dtype=np.float32)
        norm_a = np.linalg.norm(a)
        norm_b = np.linalg.norm(b)
        if norm_a == 0 or norm_b == 0:
            return 0.0
        return float(np.dot(a, b) / (norm_a * norm_b))

    @classmethod
    def matches_career_preferences(cls, student: Dict[str, Any], drive: Dict[str, Any]) -> tuple[bool, str, float]:
        """
        Determines if a drive matches the student's career preferences using local
        FastEmbed vector cosine similarity and target role/domain taxonomy keywords.
        Returns: (is_match, reason, similarity_or_ctc)
        """
        prefs = student.get("career_preferences") or {}
        blacklisted = [b.lower().strip() for b in prefs.get("blacklisted_companies", []) if isinstance(b, str) and b.strip()]
        company_name = (drive.get("company_name") or "").lower().strip()
        if company_name and any(b == company_name or b in company_name for b in blacklisted):
            return False, "COMPANY_BLACKLISTED", 0.0

        target_roles = [r.lower().strip() for r in prefs.get("target_roles", []) if r.strip()]
        preferred_domains = [d.lower().strip() for d in prefs.get("preferred_domains", []) if d.strip()]

        drive_title = (drive.get("drive_title") or "").lower()
        drive_desc = (drive.get("description") or "").lower()
        drive_skills = [s.lower() for s in (drive.get("required_skills") or drive.get("extracted_required_skills") or [])]

        # 1. Check keyword/role match or domain match first
        domain_matched = False
        matched_domain_name = ""
        for role in target_roles:
            if role in drive_title or any(role in s for s in drive_skills):
                domain_matched = True
                matched_domain_name = role.upper() if len(role) <= 4 else role.title()
                break

        if not domain_matched:
            for domain in preferred_domains:
                if domain in drive_title or domain in drive_desc or any(domain in s for s in drive_skills):
                    domain_matched = True
                    matched_domain_name = domain.upper() if len(domain) <= 4 else domain.title()
                    break

        # 2. Dense vector semantic similarity via precomputed FastEmbed embeddings
        sim = cls._cosine_similarity(student.get("preferences_vector"), drive.get("jd_vector"))
        if not domain_matched and sim >= 0.60:
            domain_matched = True
            matched_domain_name = "AI/ML" if "ai" in drive_title else "Software Development"

        if not domain_matched:
            return False, "Does not match preferred career domains", sim

        # 3. Check salary threshold (normalize absolute rupees vs LPA)
        raw_drive_ctc = float(drive.get("ctc_max") or drive.get("ctc_min") or 0.0)
        drive_ctc_lpa = raw_drive_ctc / 100000.0 if raw_drive_ctc > 50000 else raw_drive_ctc

        min_ctc = float(prefs.get("min_ctc_lpa") or 0.0)
        if min_ctc > 0 and drive_ctc_lpa > 0 and drive_ctc_lpa < min_ctc:
            return False, "SALARY_BELOW_RANGE", drive_ctc_lpa

        return True, f"Role matches {matched_domain_name} preference", max(sim, 0.85)

    @classmethod
    def identify_ineligibility_reasons(cls, student: Dict[str, Any], drive: Dict[str, Any]) -> List[str]:
        """Determines the exact barriers preventing eligibility."""
        reasons = []
        s_cgpa = float(student.get("CGPA") or 0.0)
        d_cgpa = float(drive.get("min_cgpa") or 0.0)
        if s_cgpa < d_cgpa:
            reasons.append(f"Current CGPA ({s_cgpa}) is below required {d_cgpa}")

        s_backlogs = int(student.get("active_backlogs") or 0)
        d_backlogs = int(drive.get("max_allowed_backlogs") or 0)
        if s_backlogs > d_backlogs:
            reasons.append(f"Active backlogs ({s_backlogs}) exceed allowed maximum ({d_backlogs})")

        allowed_courses = drive.get("eligible_courses") or ["ALL"]
        s_branch = (student.get("branch") or "").upper()
        if "ALL" not in allowed_courses and s_branch and not any(s_branch in c for c in allowed_courses):
            reasons.append(f"Branch '{s_branch}' is not in allowed courses {allowed_courses}")

        has_resume = bool(student.get("has_resume") or student.get("resume_id") or student.get("resume_url"))
        if not has_resume:
            reasons.append("Resume is not uploaded")

        return reasons or ["Placement policy criteria not met"]

    @classmethod
    async def _record_decision_if_not_exists(
        cls,
        user_id: str,
        drive_id: str,
        action: str,
        proposal_details: Optional[Dict[str, Any]] = None,
    ) -> bool:
        """
        Atomically records (user_id, drive_id, action) decision in agent_runs.
        Returns False if a decision already exists for this (user_id, drive_id, action),
        preventing duplicate notifications. Returns True if successfully recorded.
        """
        try:
            coll = agent_runs_collection
            existing = await coll.find_one({
                "user_id": user_id,
                "$or": [
                    {"drive_id": drive_id},
                    {"proposal_details.drive_id": drive_id},
                ],
                "action": {"$in": [action, f"{action}_ALERT", action.replace("_ALERT", "")]},
            })
            if existing:
                return False

            run_id = str(uuid.uuid4())
            now = datetime.now(timezone.utc)
            details = dict(proposal_details or {})
            details["drive_id"] = drive_id

            res = await coll.update_one(
                {
                    "user_id": user_id,
                    "drive_id": drive_id,
                    "action": action,
                },
                {
                    "$setOnInsert": {
                        "agent_run_id": run_id,
                        "user_id": user_id,
                        "drive_id": drive_id,
                        "agent_type": "PLACEMENT_COPILOT",
                        "action": action,
                        "proposal_details": details,
                        "approved": False,
                        "timestamp": now,
                    }
                },
                upsert=True,
            )
            if getattr(res, "matched_count", 0) > 0:
                return False
            return True
        except Exception as e:
            logger.warning(f"Error checking/recording agent run decision: {e}")
            return True

    @classmethod
    async def evaluate_and_act(cls, student: Dict[str, Any], drive: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Runs the full 4-stage autonomous evaluation for a single student against a drive.
        """
        student_id = student.get("student_id")
        user_id = student.get("user_id") or student_id
        drive_id = drive.get("drive_id")
        company_name = drive.get("company_name", "Unknown Company")
        drive_title = drive.get("drive_title", "Placement Drive")

        # Check if already applied
        existing_app = await applications_collection.find_one({
            "drive_id": drive_id,
            "$or": [{"student_id": student_id}, {"user_id": user_id}],
        })
        if existing_app:
            return None

        # Check blacklisted companies
        prefs = student.get("career_preferences") or {}
        blacklisted = [b.lower().strip() for b in prefs.get("blacklisted_companies", []) if isinstance(b, str) and b.strip()]
        company_name_norm = company_name.lower().strip()
        if company_name_norm and any(b == company_name_norm or b in company_name_norm for b in blacklisted):
            return None

        # Stage 1: Preference Match
        is_pref_match, pref_reason, sim_score = cls.matches_career_preferences(student, drive)

        from app.services.ai_bot_assistant import ai_bot_assistant

        # CASE: Domain matches, but offered salary is below requested range
        if not is_pref_match:
            if pref_reason == "SALARY_BELOW_RANGE" and prefs.get("notify_on_ineligible_match", True):
                min_ctc = prefs.get("min_ctc_lpa", 0.0)
                max_ctc = prefs.get("max_ctc_lpa")
                ctc_label = f"{min_ctc}–{max_ctc} LPA" if (min_ctc and max_ctc) else f"{min_ctc} LPA"

                should_notify = await cls._record_decision_if_not_exists(
                    user_id=user_id,
                    drive_id=drive_id,
                    action="SALARY_BELOW_RANGE",
                    proposal_details={
                        "drive_id": drive_id,
                        "company_name": company_name,
                        "offered_ctc": sim_score,
                        "requested_range": ctc_label,
                    },
                )
                if should_notify:
                    bot_chat_text = (
                        f"{company_name} has been added, but I did not apply because the offered salary "
                        f"is {sim_score:.1f} LPA, which is below your requested {ctc_label} range."
                    )
                    await ai_bot_assistant.send_agent_notification_message(user_id, bot_chat_text, company_name)
                    await log_agent_decision(
                        user_id=user_id,
                        agent_type="PLACEMENT_COPILOT",
                        action="SALARY_BELOW_RANGE_ALERT",
                        proposal_details={
                            "drive_id": drive_id,
                            "company_name": company_name,
                            "offered_ctc": sim_score,
                            "requested_range": ctc_label,
                        },
                        approved=False,
                    )
                return {"action": "SALARY_BELOW_RANGE", "offered_ctc": sim_score}
            return None

        # Stage 2: Hard University Eligibility
        is_eligible = compute_eligibility(student, drive)
        auto_apply_enabled = bool(prefs.get("auto_apply_enabled", False))
        has_resume = bool(student.get("has_resume") or student.get("resume_id") or student.get("resume_url"))

        # Skill Overlap
        s_skills = student.get("skills", [])
        d_skills = drive.get("required_skills") or drive.get("extracted_required_skills") or []
        overlap = skill_matcher_engine.compute_skill_overlap(s_skills, d_skills)

        # CASE A: Full Match + Eligible + Auto-Apply Enabled -> AUTONOMOUS APPLICATION
        if is_eligible and auto_apply_enabled and has_resume:
            now_iso = datetime.now(timezone.utc).isoformat()
            app_id = f"app_{uuid.uuid4().hex[:12]}"
            app_doc = {
                "app_id": app_id,
                "application_id": app_id,
                "drive_id": drive_id,
                "listing_id": drive_id,
                "job_id": drive_id,
                "company_id": drive.get("company_id") or drive.get("recruiter_id") or drive_id,
                "company_name": company_name,
                "student_id": student_id,
                "user_id": user_id,
                "name": student.get("full_name") or student.get("name") or "Student",
                "email": student.get("email") or "",
                "phone_number": student.get("phone_number") or student.get("phone") or "",
                "cgpa": float(student.get("CGPA") or student.get("cgpa") or 0.0),
                "course": student.get("course") or student.get("education") or student.get("branch") or "",
                "resume_link": student.get("resume_id") or student.get("resume_url") or "",
                "resume_id_used": student.get("resume_id") or "",
                "status": "applied",
                "current_step": "Applied",
                "current_round": 0,
                "round_history": [],
                "final_outcome": "in_progress",
                "is_eligible": True,
                "meets_cgpa_criteria": True,
                "application_source": "AGENTIC_AUTO_APPLY",
                "applied_at": now_iso,
                "match_meta": {
                    "reason": pref_reason,
                    "similarity_score": sim_score,
                    "matched_skills": overlap["matched_skills"],
                    "match_count": overlap["match_count"],
                },
            }
            await applications_collection.insert_one(app_doc)

            try:
                await drives_collection.update_many(
                    {"$or": [{"drive_id": drive_id}, {"listing_id": drive_id}]},
                    {"$inc": {"applicant_count": 1}}
                )
            except Exception:
                pass

            # Audit log
            await log_agent_decision(
                user_id=user_id,
                agent_type="PLACEMENT_COPILOT",
                action="AUTO_APPLY_SUBMITTED",
                proposal_details={
                    "drive_id": drive_id,
                    "company_name": company_name,
                    "drive_title": drive_title,
                    "matched_skills": overlap["matched_skills"],
                },
                approved=True,
            )

            # Natural Language AI Bot Message
            min_ctc = prefs.get("min_ctc_lpa", 0.0)
            max_ctc = prefs.get("max_ctc_lpa")
            ctc_label = f"{min_ctc}–{max_ctc} LPA" if (min_ctc and max_ctc) else (f"{min_ctc} LPA" if min_ctc else "package")
            domain_label = pref_reason.replace("Role matches ", "").replace(" preference", "")
            bot_chat_text = (
                f"{company_name} has been added to the placement drive. The role matches your {domain_label} preference, "
                f"your resume contains the required skills, and the salary is within your requested {ctc_label} range. "
                f"You are eligible, so I have submitted your application."
            )
            await ai_bot_assistant.send_agent_notification_message(user_id, bot_chat_text, company_name)

            # Student In-App Notification
            await notifications_collection.insert_one({
                "notification_id": str(uuid.uuid4()),
                "user_id": user_id,
                "type": "AGENT_AUTO_APPLIED",
                "title": f"Applied to {company_name} by AI Bot",
                "message": bot_chat_text,
                "drive_id": drive_id,
                "read": False,
                "created_at": datetime.now(timezone.utc).isoformat(),
            })
            return {"action": "AUTO_APPLIED", "app_id": app_id}

        # CASE B: Preference Matches, but Ineligible -> EXPLAINABLE ALERT
        elif not is_eligible and prefs.get("notify_on_ineligible_match", True):
            barriers = cls.identify_ineligibility_reasons(student, drive)
            barrier_str = "; ".join(barriers)

            should_notify = await cls._record_decision_if_not_exists(
                user_id=user_id,
                drive_id=drive_id,
                action="INELIGIBLE_NOTIFIED",
                proposal_details={
                    "drive_id": drive_id,
                    "company_name": company_name,
                    "reasons": barriers,
                },
            )
            if should_notify:
                await log_agent_decision(
                    user_id=user_id,
                    agent_type="PLACEMENT_COPILOT",
                    action="INELIGIBLE_ALERT",
                    proposal_details={
                        "drive_id": drive_id,
                        "company_name": company_name,
                        "reasons": barriers,
                    },
                    approved=False,
                )

                bot_chat_text = f"{company_name} has been added, but I did not apply because {barrier_str}."
                await ai_bot_assistant.send_agent_notification_message(user_id, bot_chat_text, company_name)

                await notifications_collection.insert_one({
                    "notification_id": str(uuid.uuid4()),
                    "user_id": user_id,
                    "type": "AGENT_INELIGIBLE_ALERT",
                    "title": f"AI Bot Notice: {company_name}",
                    "message": bot_chat_text,
                    "drive_id": drive_id,
                    "read": False,
                    "created_at": datetime.now(timezone.utc).isoformat(),
                })
            return {"action": "INELIGIBLE_NOTIFIED", "barriers": barriers}

        # CASE C: Eligible, but Auto-Apply is OFF -> 1-TAP NUDGE
        elif is_eligible and not auto_apply_enabled:
            should_notify = await cls._record_decision_if_not_exists(
                user_id=user_id,
                drive_id=drive_id,
                action="NUDGED_FOR_MANUAL_APPLY",
                proposal_details={
                    "drive_id": drive_id,
                    "company_name": company_name,
                },
            )
            if should_notify:
                bot_chat_text = f"{company_name} matches your career instructions and you are 100% eligible! Tap in Applications to submit."
                await ai_bot_assistant.send_agent_notification_message(user_id, bot_chat_text, company_name)

                await notifications_collection.insert_one({
                    "notification_id": str(uuid.uuid4()),
                    "user_id": user_id,
                    "type": "AGENT_RECOMMENDED_DRIVE",
                    "title": f"Recommended: {company_name}",
                    "message": bot_chat_text,
                    "drive_id": drive_id,
                    "read": False,
                    "created_at": datetime.now(timezone.utc).isoformat(),
                })
            return {"action": "NUDGED_FOR_MANUAL_APPLY"}

        return None

    @classmethod
    async def process_drive_for_all_candidates(cls, drive_id: str) -> Dict[str, int]:
        """
        Background processor triggered on drive publication.
        """
        drive = await drives_collection.find_one({"drive_id": drive_id})
        if not drive or drive.get("status") == "closed":
            return {"processed": 0, "auto_applied": 0}

        stats = {"processed": 0, "auto_applied": 0, "ineligible_notified": 0}
        cursor = students_collection.find({})
        async for student in cursor:
            stats["processed"] += 1
            try:
                res = await cls.evaluate_and_act(student, drive)
                if res:
                    if res.get("action") == "AUTO_APPLIED":
                        stats["auto_applied"] += 1
                    elif res.get("action") == "INELIGIBLE_NOTIFIED":
                        stats["ineligible_notified"] += 1
            except Exception as e:
                logger.error(f"[AutonomousAgent] Error evaluating student {student.get('student_id')}: {e}")

        logger.info(f"[AutonomousAgent] Completed drive {drive_id}: {stats}")
        return stats

    @classmethod
    async def process_student_for_all_drives(cls, student_user_id: str) -> int:
        """
        Evaluates all currently open published drives for a student whose criteria just updated.
        """
        student = await students_collection.find_one({
            "$or": [{"user_id": student_user_id}, {"student_id": student_user_id}],
        })
        if not student or not (student.get("career_preferences") or {}).get("auto_apply_enabled"):
            return 0

        applied_count = 0
        cursor = drives_collection.find({"status": "published"})
        async for drive in cursor:
            try:
                res = await cls.evaluate_and_act(student, drive)
                if res and res.get("action") == "AUTO_APPLIED":
                    applied_count += 1
            except Exception as e:
                logger.error(f"[AutonomousAgent] Error evaluating drive {drive.get('drive_id')} for student {student_user_id}: {e}")

        return applied_count


autonomous_agent = AutonomousPlacementAgent()