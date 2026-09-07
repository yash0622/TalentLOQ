import hashlib
import json
import logging
import re
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any

import httpx
from pydantic import BaseModel, Field

from app.config import settings
from app.database import get_ai_match_cache_collection
from app.services.skill_matcher import skill_matcher_engine

logger = logging.getLogger("talentloq.groq_matcher")

# Candidate Groq models in order of priority (Fastest & active on this Groq account)
GROQ_MODELS = [
    "openai/gpt-oss-20b",
    "openai/gpt-oss-120b",
    "qwen/qwen3.8-27b",
    "qwen/qwen3.6-27b",
    "groq/compound-mini",
]

# Pydantic Output Models
class RubricBreakdown(BaseModel):
    core_tech_score: int = Field(70, ge=0, le=100, description="Score for core programming languages, frameworks, and databases match")
    project_depth_score: int = Field(65, ge=0, le=100, description="Score for project architecture, hands-on complexity, and implementation evidence")
    role_readiness_score: int = Field(60, ge=0, le=100, description="Score for deployment/cloud, tooling, and professional maturity")
    gap_learnability_score: int = Field(75, ge=0, le=100, description="Score for how easily candidate can bridge skill gaps based on foundations")


class SemanticEquivalence(BaseModel):
    student_skill: str = Field(..., description="Skill the student possesses")
    job_requirement: str = Field(..., description="Job requirement it satisfies or translates to")
    transferability: str = Field(..., description="'Direct' | 'High' | 'Moderate'")
    reasoning: str = Field(..., description="Why this skill translates to the job requirement")


class ProjectEvidence(BaseModel):
    project_title: str = Field(..., description="Name or area of project/experience")
    evidence: str = Field(..., description="Demonstrated capability or architecture from the project")


class PredictedInterviewQuestion(BaseModel):
    question: str = Field(..., description="Targeted technical question probing gaps or edge skills")
    focus_area: str = Field(..., description="Skill or concept being probed")
    expected_concept: str = Field(..., description="Key concept or approach the interviewer expects")
    strong_signal: Optional[str] = Field(None, description="What a strong candidate articulates")
    red_flag_signal: Optional[str] = Field(None, description="What reveals shallow knowledge or memorization")


class RecruiterScreeningCheatSheet(BaseModel):
    key_strengths: List[str] = Field(default_factory=list, description="Top 2-3 technical advantages of this candidate")
    blindspots: List[str] = Field(default_factory=list, description="1-2 technical areas or gaps that need verification")
    suggested_interview_icebreaker: str = Field("Walk us through the most technically challenging problem you solved in your projects.", description="Direct conversation starter to test candidate's deepest skill")
    hiring_recommendation: str = Field("Recommended for technical evaluation", description="e.g. 'Strong Match - High Priority Interview' | 'Good Match - Verify Gaps' | 'Moderate Fit'")
    round_focus: Optional[str] = Field(None, description="Strategic objective for this specific round")


class SmartAIMatchResponse(BaseModel):
    overall_match_score: int = Field(..., ge=0, le=100, description="Calibrated composite score")
    fit_level: str = Field(..., description="'High Fit' | 'Medium Fit' | 'Needs Preparation'")
    role_archetype: str = Field("General Software Engineering", description="Detected job archetype")
    calibrated_weights: Dict[str, int] = Field(default_factory=lambda: {"core": 40, "project": 30, "readiness": 15, "learnability": 15})
    current_round: int = Field(1, ge=1, description="Interview round this evaluation is targeted for")
    rubric_breakdown: RubricBreakdown
    semantic_equivalences: List[SemanticEquivalence] = Field(default_factory=list)
    project_evidence: List[ProjectEvidence] = Field(default_factory=list)
    critical_skill_gaps: List[str] = Field(default_factory=list)
    predicted_interview_questions: List[PredictedInterviewQuestion] = Field(default_factory=list)
    recruiter_cheat_sheet: RecruiterScreeningCheatSheet
    student_prep_checklist: List[str] = Field(default_factory=list, description="48-hour actionable prep steps for the student")
    source: str = Field("groq_ai", description="'groq_ai' | 'cached' | 'heuristic_fallback' | 'tier1_heuristic_filter'")
    model_used: Optional[str] = None
    tokens_used: Optional[Dict[str, int]] = Field(None, description="Prompt, completion, and total tokens consumed")


class GroqMatcherService:
    """
    Expert AI Placement Director & Matching Engine powered by Groq LLMs.
    Employs role-adaptive rubric weights, multi-round interview progression memory,
    interviewer answer benchmarks, and project artifact evidence mining.
    """

    SYSTEM_PROMPT = """You are an elite university placement director and technical interviewer.
Analyze candidate student fit for the placement drive using the provided role-adaptive weights and round context.
- Round 1: Focus on baseline coding proficiency, data structures, and core syntax foundations.
- Round 2: Focus on project architectural depth, concurrency, system design, and trade-offs.
- Round 3+: Focus on production readiness, deployment, edge cases, and following up on previous round flags.

Compute overall_match_score = round((core*w_core + project*w_project + readiness*w_readiness + learnability*w_learnability)/100).
Fit Level: "High Fit" (>=75) | "Medium Fit" (50-74) | "Needs Preparation" (<50).

Output strictly JSON matching this schema:
{
  "overall_match_score": integer (0-100),
  "fit_level": "High Fit" | "Medium Fit" | "Needs Preparation",
  "rubric_breakdown": {
    "core_tech_score": integer (0-100),
    "project_depth_score": integer (0-100),
    "role_readiness_score": integer (0-100),
    "gap_learnability_score": integer (0-100)
  },
  "semantic_equivalences": [
    {
      "student_skill": "string",
      "job_requirement": "string",
      "transferability": "Direct" | "High" | "Moderate",
      "reasoning": "1 sentence explanation"
    }
  ],
  "project_evidence": [
    {"project_title": "string", "evidence": "1 sentence technical capability"}
  ],
  "critical_skill_gaps": ["max 3 items, 1-3 words each"],
  "predicted_interview_questions": [
    {
      "question": "string (under 25 words)",
      "focus_area": "string",
      "expected_concept": "key concept",
      "strong_signal": "1 sentence: what strong candidates articulate",
      "red_flag_signal": "1 sentence: what reveals shallow knowledge"
    }
  ],
  "recruiter_cheat_sheet": {
    "key_strengths": ["top 2 strengths"],
    "blindspots": ["1-2 blindspots"],
    "suggested_interview_icebreaker": "1 concise technical question",
    "hiring_recommendation": "1 sentence recommendation",
    "round_focus": "1 sentence: strategic objective for this specific round"
  },
  "student_prep_checklist": ["step 1 (under 10 words)", "step 2", "step 3"]
}
Limit predicted_interview_questions to max 2. Limit critical_skill_gaps to max 3. Keep responses compact."""

    @staticmethod
    def _infer_role_weights(title: str, skills: List[str]) -> tuple[str, Dict[str, int]]:
        """Dynamically adapts scoring weights based on role archetype."""
        text = (title + " " + " ".join(skills)).lower()
        if any(k in text for k in ["ai", "machine learning", "deep learning", "nlp", "vision", "data scientist"]):
            return "AI & Machine Learning", {"core": 35, "project": 35, "readiness": 15, "learnability": 15}
        if any(k in text for k in ["devops", "cloud", "sre", "infrastructure", "kubernetes", "docker"]):
            return "Cloud & DevOps", {"core": 30, "project": 20, "readiness": 35, "learnability": 15}
        if any(k in text for k in ["frontend", "react", "flutter", "mobile", "ios", "android", "ui", "ux"]):
            return "Frontend & Mobile", {"core": 35, "project": 40, "readiness": 15, "learnability": 10}
        if any(k in text for k in ["backend", "api", "database", "distributed", "golang", "microservices"]):
            return "Backend & Systems", {"core": 40, "project": 30, "readiness": 20, "learnability": 10}
        return "General Software Engineering", {"core": 40, "project": 30, "readiness": 15, "learnability": 15}

    @staticmethod
    def _prune_job_description(description: str, max_chars: int = 800) -> str:
        """Strips corporate boilerplate, perks, and EEO statements to preserve high-signal tech criteria."""
        if not description:
            return ""
        cleaned = re.sub(
            r"(?i)(equal\s+(opportunity|employment)|about\s+(the\s+company|our\s+company|us)|perks|benefits):?.*?(?=(responsibilities|requirements|qualifications|\Z))",
            "",
            description,
            flags=re.DOTALL,
        )
        cleaned = re.sub(r"\s+", " ", cleaned).strip()
        return cleaned[:max_chars]

    @staticmethod
    def _sanitize_projects(projects: List[Any], max_count: int = 3) -> List[str]:
        """Converts raw project dicts into lean, high-information strings with repo and architecture signals."""
        out = []
        for p in (projects or [])[:max_count]:
            if isinstance(p, dict):
                title = p.get("title") or p.get("name") or "Project"
                techs = p.get("technologies") or p.get("tech_stack") or []
                tech_str = f" [{', '.join(techs[:4])}]" if techs else ""
                gh = p.get("github_url") or p.get("repo_url") or p.get("github")
                gh_str = f" (Repo: {gh})" if gh else ""
                desc = str(p.get("description", ""))[:120].strip()
                out.append(f"{title}{tech_str}{gh_str}: {desc}" if desc else f"{title}{tech_str}{gh_str}")
            elif isinstance(p, str):
                out.append(p[:140].strip())
        return out

    @staticmethod
    def _sanitize_internships(internships: List[Any], max_count: int = 2) -> List[str]:
        """Converts raw internship dicts into lean, high-information strings."""
        out = []
        for i in (internships or [])[:max_count]:
            if isinstance(i, dict):
                role = i.get("role_title") or i.get("role") or "Intern"
                comp = i.get("company_name") or i.get("company") or "Company"
                desc = str(i.get("description", ""))[:100].strip()
                out.append(f"{role} at {comp}: {desc}" if desc else f"{role} at {comp}")
            elif isinstance(i, str):
                out.append(i[:120].strip())
        return out

    @classmethod
    def _compute_cache_key(
        cls,
        student_id: str,
        drive_id: str,
        student_skills: List[Any],
        req_skills: List[Any],
        current_round: int = 1,
        round_notes_hash: str = "",
    ) -> str:
        s_part = ",".join(sorted([str(s).strip().lower() for s in (student_skills or []) if s and str(s).strip()]))
        d_part = ",".join(sorted([str(s).strip().lower() for s in (req_skills or []) if s and str(s).strip()]))
        hash_val = hashlib.md5(f"{s_part}|{d_part}|r{current_round}|{round_notes_hash}".encode()).hexdigest()[:12]
        return f"{student_id}_{drive_id}_r{current_round}_{hash_val}"

    @classmethod
    async def analyze_match(
        cls,
        student_doc: Dict[str, Any],
        drive_doc: Dict[str, Any],
        current_round: int = 1,
        round_history: Optional[List[Dict[str, Any]]] = None,
        bypass_cache: bool = False,
    ) -> SmartAIMatchResponse:
        """
        Main entry point for multi-dimensional AI Match analysis.
        Checks MongoDB cache first. On miss, calls Groq API with fallback models.
        If all Groq calls fail or key is missing, uses calibrated heuristic fallback.
        """
        student_id = str(student_doc.get("student_id") or student_doc.get("user_id") or "unknown_student")
        drive_id = str(drive_doc.get("drive_id") or drive_doc.get("listing_id") or "unknown_drive")

        # Normalize student data
        student_skills = student_doc.get("skills") or []
        deployment_skills = student_doc.get("deployment_skills") or []
        internships = student_doc.get("internships") or []
        projects = student_doc.get("projects") or []

        # Normalize drive data
        req_skills = drive_doc.get("required_skills") or drive_doc.get("extracted_required_skills") or []
        if not req_skills:
            req_skills = skill_matcher_engine.extract_skills_from_text(drive_doc.get("description", ""))
        if not req_skills:
            req_skills = ["Software Engineering", "Problem Solving", "Communication"]

        company_name = drive_doc.get("company_name", "Company")
        drive_title = drive_doc.get("drive_title") or drive_doc.get("interview_job") or "Placement Role"
        description = drive_doc.get("description", "")

        # Infer dynamic role weights
        role_archetype, weights = cls._infer_role_weights(drive_title, req_skills)

        # Hash previous round notes for round-aware caching
        prev_notes_summary = ""
        if round_history:
            prev_notes_summary = " | ".join([
                f"R{r.get('round_number', i+1)}: {r.get('notes') or r.get('feedback') or r.get('result', '')}"
                for i, r in enumerate(round_history)
            ])
        round_notes_hash = hashlib.md5(prev_notes_summary.encode()).hexdigest()[:8] if prev_notes_summary else ""

        # 1. Check MongoDB Cache
        cache_key = cls._compute_cache_key(student_id, drive_id, student_skills, req_skills, current_round, round_notes_hash)
        cache_col = get_ai_match_cache_collection()
        if not bypass_cache and cache_col is not None:
            try:
                cached = await cache_col.find_one({"cache_key": cache_key})
                if cached and "analysis" in cached:
                    analysis_data = cached["analysis"]
                    analysis_data["source"] = "cached"
                    return SmartAIMatchResponse(**analysis_data)
            except Exception as e:
                logger.warning(f"Cache lookup failed for {cache_key}: {e}")

        # 2. Tier 1 Algorithmic Gatekeeper (Fast-path for extreme skill mismatch)
        overlap_info = skill_matcher_engine.compute_skill_overlap(student_skills, req_skills)
        if overlap_info["overlap_ratio"] < 0.15 and len(student_skills) > 0 and len(req_skills) >= 2:
            logger.info("Tier 1 fast-filter engaged for student=%s, drive=%s: overlap=%.2f", student_id, drive_id, overlap_info["overlap_ratio"])
            tier1_res = cls._compute_heuristic_fallback(
                student_skills=student_skills,
                deployment_skills=deployment_skills,
                internships=internships,
                projects=projects,
                req_skills=req_skills,
                company_name=company_name,
                drive_title=drive_title,
                current_round=current_round,
                round_history=round_history,
                role_archetype=role_archetype,
                weights=weights,
            )
            tier1_res.source = "tier1_heuristic_filter"
            if cache_col is not None:
                try:
                    await cache_col.update_one(
                        {"cache_key": cache_key},
                        {"$set": {"analysis": tier1_res.model_dump(), "created_at": datetime.now(timezone.utc)}},
                        upsert=True,
                    )
                except Exception as e:
                    logger.debug("Failed to cache tier1 result: %s", e)
            return tier1_res

        # 3. Call Free LLM Providers (Groq -> OpenRouter Free -> Mistral)
        clean_desc = cls._prune_job_description(description)
        clean_projects = cls._sanitize_projects(projects)
        clean_internships = cls._sanitize_internships(internships)

        user_prompt = f"""Candidate:
- Current Campus Round: Round {current_round}
{f"- Previous Round Interviewer Feedback: {prev_notes_summary}" if prev_notes_summary else ""}
- Skills: {student_skills[:15]}
- Cloud/DevOps: {deployment_skills[:8]}
- Internships: {clean_internships}
- Projects (with verified code artifacts): {clean_projects}

Placement Role:
- Company: {company_name}
- Title: {drive_title} (Archetype: {role_archetype})
- Calibrated Rubric Weights: Core {weights['core']}%, Project {weights['project']}%, Readiness {weights['readiness']}%, Learnability {weights['learnability']}%
- Required Skills: {req_skills[:12]}
- Requirements: {clean_desc}
"""
        api_targets = []
        if settings.GROQ_API_KEY:
            for m in GROQ_MODELS:
                api_targets.append(("https://api.groq.com/openai/v1/chat/completions", settings.GROQ_API_KEY, m, "groq_ai"))
        if settings.OPENROUTER_API_KEY:
            api_targets.append(("https://openrouter.ai/api/v1/chat/completions", settings.OPENROUTER_API_KEY, "qwen/qwen-2.5-coder-32b-instruct:free", "openrouter_free"))
            api_targets.append(("https://openrouter.ai/api/v1/chat/completions", settings.OPENROUTER_API_KEY, "meta-llama/llama-3.3-70b-instruct:free", "openrouter_free"))
        if settings.MISTRAL_API_KEY:
            api_targets.append(("https://api.mistral.ai/v1/chat/completions", settings.MISTRAL_API_KEY, "mistral-small-latest", "mistral_ai"))

        if api_targets:
            async with httpx.AsyncClient(timeout=14.0) as client:
                for endpoint_url, api_key, model, provider_tag in api_targets:
                    try:
                        resp = await client.post(
                            endpoint_url,
                            headers={
                                "Authorization": f"Bearer {api_key}",
                                "Content-Type": "application/json",
                            },
                            json={
                                "model": model,
                                "messages": [
                                    {"role": "system", "content": cls.SYSTEM_PROMPT},
                                    {"role": "user", "content": user_prompt},
                                ],
                                "response_format": {"type": "json_object"},
                                "temperature": 0.2,
                            },
                        )
                        if resp.status_code == 200:
                            raw_resp = resp.json()
                            usage = raw_resp.get("usage", {})
                            p_tok = int(usage.get("prompt_tokens") or 0)
                            c_tok = int(usage.get("completion_tokens") or 0)
                            t_tok = int(usage.get("total_tokens") or (p_tok + c_tok))

                            # Print prominent token metrics directly to the server terminal
                            print(
                                f"\n\033[1;36m+==================== [AI API TOKEN USAGE] ====================+\033[0m\n"
                                f"  \033[1mAPI Endpoint:\033[0m      {endpoint_url}\n"
                                f"  \033[1mProvider:\033[0m          {provider_tag.upper()}\n"
                                f"  \033[1mModel:\033[0m             {model}\n"
                                f"  \033[1;33mPrompt Tokens:\033[0m     {p_tok:,}\n"
                                f"  \033[1;32mCompletion Tokens:\033[0m {c_tok:,}\n"
                                f"  \033[1;35mTotal Tokens Used:\033[0m {t_tok:,}\n"
                                f"\033[1;36m+==============================================================+\033[0m\n",
                                flush=True
                            )
                            logger.info(
                                "[AI Token Usage] Provider: %s | Model: %s | Prompt: %d | Completion: %d | Total: %d",
                                provider_tag, model, p_tok, c_tok, t_tok
                            )

                            content = raw_resp["choices"][0]["message"]["content"]
                            clean_json_str = cls._clean_json(content)
                            data = json.loads(clean_json_str)

                            # Extract rubric safely with key normalization
                            r_raw = data.get("rubric_breakdown") or {}
                            if "core_tech" in r_raw and "core_tech_score" not in r_raw:
                                r_raw["core_tech_score"] = r_raw["core_tech"]
                            if "project_depth" in r_raw and "project_depth_score" not in r_raw:
                                r_raw["project_depth_score"] = r_raw["project_depth"]
                            if "role_readiness" in r_raw and "role_readiness_score" not in r_raw:
                                r_raw["role_readiness_score"] = r_raw["role_readiness"]
                            if "gap_learnability" in r_raw and "gap_learnability_score" not in r_raw:
                                r_raw["gap_learnability_score"] = r_raw["gap_learnability"]

                            # Validate schema
                            validated = SmartAIMatchResponse(
                                overall_match_score=int(data.get("overall_match_score", 65)),
                                fit_level=str(data.get("fit_level", "Medium Fit")),
                                role_archetype=role_archetype,
                                calibrated_weights=weights,
                                current_round=current_round,
                                rubric_breakdown=RubricBreakdown(**r_raw),
                                semantic_equivalences=[
                                    SemanticEquivalence(**eq) for eq in data.get("semantic_equivalences", [])
                                    if isinstance(eq, dict) and eq.get("student_skill") and eq.get("job_requirement")
                                ],
                                project_evidence=[
                                    ProjectEvidence(**pe) for pe in data.get("project_evidence", [])
                                    if isinstance(pe, dict) and pe.get("project_title")
                                ],
                                critical_skill_gaps=[str(g) for g in data.get("critical_skill_gaps", []) if g][:3],
                                predicted_interview_questions=[
                                    PredictedInterviewQuestion(**pq)
                                    for pq in data.get("predicted_interview_questions", [])
                                    if isinstance(pq, dict) and pq.get("question")
                                ][:2],
                                recruiter_cheat_sheet=RecruiterScreeningCheatSheet(
                                    **(data.get("recruiter_cheat_sheet") or {})
                                ),
                                student_prep_checklist=[str(c) for c in data.get("student_prep_checklist", []) if c][:3],
                                source=provider_tag,
                                model_used=model,
                                tokens_used={"prompt_tokens": p_tok, "completion_tokens": c_tok, "total_tokens": t_tok},
                            )

                            # Save to Cache in background
                            await cls._save_to_cache(cache_key, student_id, drive_id, validated.model_dump())
                            return validated

                        elif resp.status_code == 429:
                            logger.warning(f"Provider {provider_tag} model {model} rate limited (429), attempting next.")
                            continue
                        else:
                            logger.warning(f"Provider {provider_tag} model {model} returned {resp.status_code}: {resp.text[:100]}")
                    except Exception as e:
                        logger.warning(f"Call to {provider_tag} ({model}) failed: {e}")
                        continue

        # 3. Deterministic Heuristic Fallback
        logger.info(f"Using heuristic fallback for student {student_id} and drive {drive_id}")
        fallback = cls._compute_heuristic_fallback(
            student_skills=student_skills,
            deployment_skills=deployment_skills,
            internships=internships,
            projects=projects,
            req_skills=req_skills,
            company_name=company_name,
            drive_title=drive_title,
        )

        cache_col = get_ai_match_cache_collection()
        if cache_col is not None:
            try:
                await cls._save_to_cache(cache_key, student_id, drive_id, fallback.model_dump())
            except Exception:
                pass

        return fallback

    @classmethod
    def _clean_json(cls, raw: str) -> str:
        return raw.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip()

    @classmethod
    async def _save_to_cache(cls, cache_key: str, student_id: str, drive_id: str, data: Dict[str, Any]) -> None:
        try:
            cache_col = get_ai_match_cache_collection()
            if cache_col is not None:
                doc = {
                    "cache_key": cache_key,
                    "student_id": student_id,
                    "drive_id": drive_id,
                    "analysis": data,
                    "created_at": datetime.now(timezone.utc),
                }
                await cache_col.update_one(
                    {"cache_key": cache_key},
                    {"$set": doc},
                    upsert=True,
                )
        except Exception as e:
            logger.warning(f"Failed to persist AI match cache: {e}")

    @classmethod
    def _compute_heuristic_fallback(
        cls,
        student_skills: List[str],
        deployment_skills: List[str],
        internships: List[Any],
        projects: List[Any],
        req_skills: List[str],
        company_name: str,
        drive_title: str,
        current_round: int = 1,
        round_history: Optional[List[Dict[str, Any]]] = None,
        role_archetype: Optional[str] = None,
        weights: Optional[Dict[str, int]] = None,
    ) -> SmartAIMatchResponse:
        """
        Calibrated mathematical fallback when Groq is unreachable.
        Calculates all 4 pillars using role-adaptive weights and generates structured benchmarks.
        """
        if not role_archetype or not weights:
            role_archetype, weights = cls._infer_role_weights(drive_title, req_skills)

        overlap = skill_matcher_engine.compute_skill_overlap(student_skills, req_skills)
        matched = overlap["matched_skills"]
        missing = overlap["missing_skills"]
        match_count = overlap["match_count"]
        total_req = max(1, overlap["total_required"])

        # 1. Core Tech Score
        overlap_ratio = match_count / total_req
        core_tech_score = int(min(100, overlap_ratio * 100))

        # 2. Project Depth Score
        project_depth_score = 50
        work_evidence = (projects or []) + (internships or [])
        if work_evidence:
            project_depth_score = min(100, 65 + len(work_evidence) * 15)

        # 3. Role Readiness Score
        role_readiness_score = 40
        if deployment_skills:
            role_readiness_score += min(35, len(deployment_skills) * 10)
        if internships:
            role_readiness_score += min(25, len(internships) * 15)
        role_readiness_score = min(100, role_readiness_score)

        # 4. Gap Learnability Score
        if len(student_skills) >= 10:
            gap_learnability_score = 85
        elif len(student_skills) >= 5:
            gap_learnability_score = 75
        else:
            gap_learnability_score = 60

        # Calibrated Overall Score using Dynamic Weights
        w_c = weights.get("core", 40) / 100.0
        w_p = weights.get("project", 30) / 100.0
        w_r = weights.get("readiness", 15) / 100.0
        w_l = weights.get("learnability", 15) / 100.0

        overall = int(round(
            w_c * core_tech_score
            + w_p * project_depth_score
            + w_r * role_readiness_score
            + w_l * gap_learnability_score
        ))

        fit_level = "High Fit" if overall >= 75 else ("Medium Fit" if overall >= 50 else "Needs Preparation")

        # Semantic Equivalences
        equivalences: List[SemanticEquivalence] = []
        for ms in matched:
            equivalences.append(
                SemanticEquivalence(
                    student_skill=ms,
                    job_requirement=ms,
                    transferability="Direct",
                    reasoning=f"Candidate has direct verified background in {ms}.",
                )
            )

        student_lower = [s.lower() for s in student_skills]
        if "fastapi" in student_lower and any("django" in r.lower() for r in req_skills):
            equivalences.append(
                SemanticEquivalence(
                    student_skill="FastAPI",
                    job_requirement="Django / Python Web",
                    transferability="High",
                    reasoning="Python web API architecture and asynchronous request handling translate directly.",
                )
            )
        if "mongodb" in student_lower and any("sql" in r.lower() or "postgres" in r.lower() for r in req_skills):
            equivalences.append(
                SemanticEquivalence(
                    student_skill="MongoDB",
                    job_requirement="Database / SQL",
                    transferability="Moderate",
                    reasoning="Database indexing, aggregation, and query optimization fundamentals transfer well.",
                )
            )

        # Project Evidence with Repo/Artifact Details
        evidence_list: List[ProjectEvidence] = []
        for p in projects[:3]:
            title = p.get("title") if isinstance(p, dict) else str(p)
            desc = p.get("description") if isinstance(p, dict) else "Implemented project application."
            gh = p.get("github_url") or p.get("repo_url") if isinstance(p, dict) else None
            extra = f" (Repo: {gh})" if gh else ""
            evidence_list.append(
                ProjectEvidence(
                    project_title=(title or "Core Technical Project") + extra,
                    evidence=desc or "Applied core programming and architectural patterns.",
                )
            )

        # Round Focus & Objectives
        if current_round == 1:
            round_focus = "Round 1 Objective: Validate core syntax, fundamental problem-solving, and foundational logic."
        elif current_round == 2:
            round_focus = "Round 2 Objective: Deep-dive into project architecture, API concurrency, and design trade-offs."
        else:
            round_focus = f"Round {current_round} Objective: Production readiness, cloud deployment, resilience, and behavioral STAR fit."

        # Predicted Interview Questions with Answer Benchmarks
        questions: List[PredictedInterviewQuestion] = []
        if missing:
            primary_gap = missing[0]
            questions.append(
                PredictedInterviewQuestion(
                    question=f"How would you apply your existing engineering foundations to quickly solve a real-world problem using {primary_gap}?",
                    focus_area=primary_gap,
                    expected_concept=f"Core concepts, syntax, and architecture of {primary_gap}",
                    strong_signal=f"Articulates fundamental architectural trade-offs and rapid onboarding plan with standard patterns.",
                    red_flag_signal=f"Defensive about missing {primary_gap} or cannot explain core programming analogs.",
                )
            )
        if matched:
            top_skill = matched[0]
            questions.append(
                PredictedInterviewQuestion(
                    question=f"Can you walk us through how you designed and optimized the architecture of your {top_skill} implementation?",
                    focus_area=top_skill,
                    expected_concept="Scalability, modular design, error handling, and performance tuning",
                    strong_signal="Walks through performance profiling, edge-case failure modes, and architectural trade-offs.",
                    red_flag_signal="Only recites high-level tutorial steps without explaining internal mechanics or design decisions.",
                )
            )
        questions.append(
            PredictedInterviewQuestion(
                question="How do you approach debugging and profiling performance bottlenecks in a production environment?",
                focus_area="System Reliability",
                expected_concept="Logging, monitoring, profiling, and root-cause analysis",
                strong_signal="Describes structured observability (metrics, logs, traces) and reproduces issues methodically.",
                red_flag_signal="Relies solely on trial-and-error print debugging without understanding latency metrics.",
            )
        )

        # Recruiter Cheat Sheet
        cheat_sheet = RecruiterScreeningCheatSheet(
            key_strengths=[
                f"Possesses {len(matched)} matching core skills including {', '.join(matched[:3]) if matched else 'foundational skills'}.",
                f"Has {len(deployment_skills)} cloud/deployment tools and {len(internships)} internship experiences." if deployment_skills or internships else "Demonstrates practical project implementations.",
            ],
            blindspots=missing[:2] if missing else ["Verify architectural depth during technical deep-dive."],
            suggested_interview_icebreaker=f"Ask candidate to walk through their most challenging project and how they handled unexpected edge cases.",
            hiring_recommendation=f"{fit_level} for {drive_title} at {company_name}. Recommended for {round_focus}.",
            round_focus=round_focus,
        )

        # Prep Checklist
        prep_checklist = [
            f"Revise core principles and practical interview questions for {', '.join(missing[:2])}." if missing else "Review advanced system design and architecture patterns.",
            f"Prepare a 2-minute architectural deep dive for your top projects.",
            f"Review standard behavioral questions using the STAR framework.",
        ]

        return SmartAIMatchResponse(
            overall_match_score=overall,
            fit_level=fit_level,
            role_archetype=role_archetype,
            calibrated_weights=weights,
            current_round=current_round,
            rubric_breakdown=RubricBreakdown(
                core_tech_score=core_tech_score,
                project_depth_score=project_depth_score,
                role_readiness_score=role_readiness_score,
                gap_learnability_score=gap_learnability_score,
            ),
            semantic_equivalences=equivalences,
            project_evidence=evidence_list,
            critical_skill_gaps=missing[:3],
            predicted_interview_questions=questions[:2],
            recruiter_cheat_sheet=cheat_sheet,
            student_prep_checklist=prep_checklist[:3],
            source="heuristic_fallback",
            model_used=None,
        )


groq_matcher_service = GroqMatcherService()