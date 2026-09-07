"""
Talent Comparator & Multi-Candidate Ranking Engine.
Evaluates and ranks matching students across:
1. Core Technical Skills (40%)
2. Deployment & DevOps Knowledge (30%)
3. Number & Quality of Internships (30%)
"""
import logging
from typing import List, Dict, Any, Optional
from app.services.skill_matcher import skill_matcher_engine

logger = logging.getLogger("talentloq.talent_comparator")

# Canonical deployment keywords grouped by domain
DEPLOYMENT_TAXONOMY = {
    "containers": {"docker", "kubernetes", "k8s", "helm", "podman", "containerd"},
    "cloud": {"aws", "amazon web services", "gcp", "google cloud", "google cloud platform", "azure", "microsoft azure", "terraform", "cloudformation"},
    "cicd_hosting": {"ci/cd", "cicd", "github actions", "gitlab ci", "jenkins", "nginx", "linux", "vercel", "netlify", "ansible", "cloudflare", "heroku"}
}

ALL_DEPLOYMENT_KEYWORDS = set().union(*DEPLOYMENT_TAXONOMY.values())


class TalentComparatorService:
    @staticmethod
    def _safe_float(val: Any, default: float = 0.0) -> float:
        if val is None:
            return default
        try:
            cleaned = str(val).split("/")[0].strip()
            return float(cleaned)
        except (ValueError, TypeError):
            return default

    @staticmethod
    def compute_deployment_score(skills: List[str], deployment_skills: Optional[List[str]] = None) -> tuple[float, List[str]]:
        """
        Computes 0-100 score based on containerization, cloud, and CI/CD/hosting knowledge.
        Returns (score, detected_deployment_skills).
        """
        combined = set()
        for s in (skills or []):
            combined.add(s.lower().strip())
        for s in (deployment_skills or []):
            combined.add(s.lower().strip())

        detected = set()
        has_containers = False
        has_cloud = False
        has_cicd = False

        for word in combined:
            for canon in ALL_DEPLOYMENT_KEYWORDS:
                if canon == word or canon in word:
                    # Map to clean title
                    display = canon.upper() if canon in ["aws", "gcp", "ci/cd", "cicd", "k8s"] else canon.title()
                    if canon in ["ci/cd", "cicd"]:
                        display = "CI/CD"
                    detected.add(display)
                    if canon in DEPLOYMENT_TAXONOMY["containers"]:
                        has_containers = True
                    if canon in DEPLOYMENT_TAXONOMY["cloud"]:
                        has_cloud = True
                    if canon in DEPLOYMENT_TAXONOMY["cicd_hosting"]:
                        has_cicd = True

        # Scoring tiers: Containers (35pts) + Cloud (35pts) + CI/CD/Hosting (30pts)
        score = 0.0
        if has_containers:
            score += 35.0
        if has_cloud:
            score += 35.0
        if has_cicd:
            score += 30.0

        # Partial credit: if candidate has 1 tool from a domain, give baseline
        if not (has_containers or has_cloud or has_cicd) and detected:
            score = min(40.0, len(detected) * 20.0)

        return min(100.0, round(score, 1)), sorted(list(detected))

    @staticmethod
    def compute_internship_score(internship_count: int, internships: Optional[List[Dict[str, Any]]] = None) -> float:
        """
        Quantifies work experience into a 0-100 scale:
        - 0 internships: 0 pts
        - 1 internship: 65 pts
        - 2 internships: 85 pts
        - 3+ internships: 100 pts
        """
        count = max(int(internship_count or 0), len(internships or []))
        if count <= 0:
            return 0.0
        elif count == 1:
            return 65.0
        elif count == 2:
            return 85.0
        else:
            return 100.0

    @classmethod
    def evaluate_candidate(
        cls,
        student: Dict[str, Any],
        required_skills: List[str]
    ) -> Dict[str, Any]:
        """
        Evaluates a single student against job requirements across the 3 pillars.
        """
        student_skills = student.get("skills") or student.get("technical_skills") or []
        student_dep_skills = student.get("deployment_skills") or []
        internship_list = student.get("internships") or []
        internship_count = int(student.get("internship_count") or len(internship_list))

        # 1. Core Technical Skills Match (40%)
        overlap = skill_matcher_engine.compute_skill_overlap(student_skills, required_skills)
        match_cnt = overlap.get("match_count", 0)
        tot_req = overlap.get("total_required", 1)
        skill_score = round((match_cnt / tot_req) * 100, 1) if tot_req > 0 else 100.0

        # 2. Deployment Knowledge Score (30%)
        dep_score, detected_dep = cls.compute_deployment_score(student_skills, student_dep_skills)

        # 3. Internship Experience Score (30%)
        internship_score = cls.compute_internship_score(internship_count, internship_list)

        # Composite Rank Score: 40% Skills + 30% Deployment + 30% Internships
        composite_score = round(
            (0.40 * skill_score) + (0.30 * dep_score) + (0.30 * internship_score),
            1
        )

        # Generate strengths summary
        strengths = []
        if skill_score >= 70:
            strengths.append(f"Strong skill match ({int(skill_score)}%)")
        if detected_dep:
            strengths.append(f"DevOps/Cloud: {', '.join(detected_dep[:3])}")
        if internship_count > 0:
            strengths.append(f"{internship_count} Internship{'s' if internship_count > 1 else ''}")
        if not strengths:
            strengths.append("Foundational applicant")

        return {
            "student_id": student.get("student_id") or student.get("user_id") or str(student.get("_id", "")),
            "name": student.get("full_name") or student.get("name") or "Student Candidate",
            "email": student.get("email", ""),
            "cgpa": cls._safe_float(student.get("CGPA") or student.get("cgpa")),
            "course": student.get("education") or student.get("course") or "Engineering",
            "branch": student.get("branch") or "CSE",
            "composite_score": composite_score,
            "skill_score": skill_score,
            "deployment_score": dep_score,
            "internship_score": internship_score,
            "matched_skills": overlap.get("matched_skills", []),
            "missing_skills": overlap.get("missing_skills", []),
            "deployment_skills": detected_dep,
            "internship_count": internship_count,
            "internships": internship_list,
            "strengths_summary": " • ".join(strengths),
            "resume_url": student.get("resume_url") or "",
            "has_resume": bool(student.get("has_resume", False)),
        }

    @classmethod
    def rank_candidates(
        cls,
        students: List[Dict[str, Any]],
        required_skills: List[str]
    ) -> List[Dict[str, Any]]:
        """
        Ranks a list of students descending by composite score, breaking ties by CGPA.
        """
        evaluated = [cls.evaluate_candidate(s, required_skills) for s in students]

        # Sort: Primary by composite_score DESC, Secondary by CGPA DESC
        evaluated.sort(key=lambda x: (x["composite_score"], x["cgpa"]), reverse=True)

        # Assign ranks
        for idx, cand in enumerate(evaluated):
            cand["rank"] = idx + 1

        return evaluated
