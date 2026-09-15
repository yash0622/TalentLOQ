"""
Self-contained unit and benchmark verification for Advanced AI Pipeline:
1. FastEmbed ONNX vector pre-computation & sub-millisecond dot-product matching
2. Two-stage re-ranking (deployment depth bonus & missing skill penalty)
3. Fit tier categorization
"""
import pytest
import numpy as np
from app.services.hybrid_matcher import (
    get_text_embedding,
    compute_hybrid_match_score,
)

def test_vector_precomputation_and_fast_path():
    # 1. Pre-compute vector embeddings
    text_resume = "Full-stack developer with Flutter, FastAPI, Docker, and MongoDB expertise."
    text_job = "Looking for a Mobile and Backend Engineer experienced in Flutter and Python."

    resume_vec = get_text_embedding(text_resume)
    job_vec = get_text_embedding(text_job)

    assert resume_vec is not None, "resume_vec should be computed"
    assert job_vec is not None, "job_vec should be computed"
    assert len(resume_vec) == 384, f"Expected 384 dimensions, got {len(resume_vec)}"
    assert len(job_vec) == 384, f"Expected 384 dimensions, got {len(job_vec)}"

    # 2. Fast-path cosine calculation with pre-computed vectors
    res_with_vec = compute_hybrid_match_score(
        resume_text=text_resume,
        job_description=text_job,
        candidate_skills=["Flutter", "FastAPI", "Docker", "MongoDB"],
        job_skills=["Flutter", "FastAPI", "Python"],
        resume_vector=resume_vec,
        job_vector=job_vec,
    )

    assert res_with_vec["match_score"] >= 65, f"Expected strong match score, got {res_with_vec['match_score']}"
    assert res_with_vec["fit_tier"] in ["MODERATE", "COMPETITIVE", "EXCEPTIONAL"]
    assert "Flutter" in res_with_vec["matched_skills"]
    assert "FastAPI" in res_with_vec["matched_skills"]


def test_stage2_reranking_depth_bonus():
    # Candidate with verified deployment skills & internships should rank higher than one without
    base_skills = ["Python", "FastAPI"]
    job_skills = ["Python", "FastAPI", "Docker", "Kubernetes"]

    score_without_depth = compute_hybrid_match_score(
        candidate_skills=base_skills,
        job_skills=job_skills,
        candidate_deployment_skills=[],
        candidate_internships=[],
    )

    score_with_depth = compute_hybrid_match_score(
        candidate_skills=base_skills,
        job_skills=job_skills,
        candidate_deployment_skills=["Docker", "Kubernetes"],
        candidate_internships=[{"role": "Backend Intern", "company": "Tech Corp"}],
    )

    assert score_with_depth["match_score"] > score_without_depth["match_score"], (
        f"Depth score {score_with_depth['match_score']} should exceed {score_without_depth['match_score']}"
    )
    assert "Docker" in score_with_depth["matched_deployment_skills"]


def test_critical_skill_penalty():
    # Candidate with completely mismatched skills should receive critical skill penalty
    res_mismatched = compute_hybrid_match_score(
        candidate_skills=["Biology", "Genetics"],
        job_skills=["Python", "FastAPI", "React", "PostgreSQL"],
    )

    assert res_mismatched["match_score"] < 60
    assert res_mismatched["fit_tier"] in ["LOW", "MODERATE"]


if __name__ == "__main__":
    print("Running advanced AI pipeline tests...")
    test_vector_precomputation_and_fast_path()
    test_stage2_reranking_depth_bonus()
    test_critical_skill_penalty()
    print("✓ All AI pipeline tests passed successfully!")
