import pytest
from app.services.groq_matcher import GroqMatcherService, SmartAIMatchResponse

@pytest.mark.asyncio
async def test_heuristic_fallback():
    student_doc = {
        "student_id": "STU_TEST_001",
        "skills": ["Python", "FastAPI", "MongoDB", "Docker", "Git"],
        "deployment_skills": ["Docker", "Git", "Linux"],
        "internships": [{"company_name": "TestCorp", "role_title": "Intern"}],
        "projects": [{"title": "API Gateway", "description": "Built FastAPI gateway with JWT auth"}],
    }
    drive_doc = {
        "drive_id": "DRV_TEST_001",
        "company_name": "Acme Corp",
        "drive_title": "Backend Python Engineer",
        "required_skills": ["Python", "Django", "PostgreSQL", "Docker", "Git"],
        "description": "Backend role requiring Python, Django, PostgreSQL, and Docker.",
    }

    # Test deterministic heuristic directly
    fallback = GroqMatcherService._compute_heuristic_fallback(
        student_skills=student_doc["skills"],
        deployment_skills=student_doc["deployment_skills"],
        internships=student_doc["internships"],
        projects=student_doc["projects"],
        req_skills=drive_doc["required_skills"],
        company_name=drive_doc["company_name"],
        drive_title=drive_doc["drive_title"],
    )

    assert isinstance(fallback, SmartAIMatchResponse)
    assert 0 <= fallback.overall_match_score <= 100
    assert fallback.rubric_breakdown.core_tech_score > 0
    assert fallback.rubric_breakdown.project_depth_score > 0
    assert fallback.rubric_breakdown.role_readiness_score > 0
    assert fallback.rubric_breakdown.gap_learnability_score > 0
    assert len(fallback.predicted_interview_questions) >= 1
    assert len(fallback.recruiter_cheat_sheet.key_strengths) >= 1
    assert len(fallback.student_prep_checklist) >= 1
    assert fallback.source == "heuristic_fallback"

@pytest.mark.asyncio
async def test_analyze_match_execution():
    student_doc = {
        "student_id": "STU_TEST_002",
        "skills": ["Python", "FastAPI", "Docker"],
        "deployment_skills": ["Docker"],
        "internships": [],
        "projects": [{"title": "Chat App", "description": "WebSockets chat in Python"}],
    }
    drive_doc = {
        "drive_id": "DRV_TEST_002",
        "company_name": "Beta Labs",
        "drive_title": "Python Developer",
        "required_skills": ["Python", "Docker"],
        "description": "Looking for Python and Docker developer.",
    }

    result = await GroqMatcherService.analyze_match(student_doc, drive_doc)
    assert isinstance(result, SmartAIMatchResponse)
    assert 0 <= result.overall_match_score <= 100
    assert result.fit_level in ["High Fit", "Medium Fit", "Needs Preparation"]
    assert result.source in ["groq_ai", "cached", "heuristic_fallback"]


@pytest.mark.asyncio
async def test_caching_behavior():
    student_doc = {
        "student_id": "STU_CACHE_TEST",
        "skills": ["Java", "Spring Boot", "SQL"],
        "deployment_skills": ["Docker"],
        "internships": [],
        "projects": [{"title": "Banking System", "description": "Spring Boot microservices"}],
    }
    drive_doc = {
        "drive_id": "DRV_CACHE_TEST",
        "company_name": "FinTech Corp",
        "drive_title": "Java Backend Engineer",
        "required_skills": ["Java", "SQL"],
        "description": "Backend Java engineer role.",
    }

    # First call - computes and caches
    first_res = await GroqMatcherService.analyze_match(student_doc, drive_doc, bypass_cache=True)
    assert isinstance(first_res, SmartAIMatchResponse)

    # Second call - should hit cache
    second_res = await GroqMatcherService.analyze_match(student_doc, drive_doc, bypass_cache=False)
    assert isinstance(second_res, SmartAIMatchResponse)
    assert second_res.source == "cached"
    assert second_res.overall_match_score == first_res.overall_match_score


@pytest.mark.asyncio
async def test_tier1_gatekeeper_and_pruning():
    """Verifies that completely mismatched candidates hit tier1 gatekeeper without LLM calls."""
    student_doc = {
        "student_id": "STU_MISMATCH_001",
        "skills": ["Flutter", "Dart", "Mobile Development"],
        "deployment_skills": [],
        "internships": [{"role_title": "Flutter Developer", "company_name": "AppStudio", "description": "Built iOS app"}],
        "projects": [{"title": "Fitness App", "technologies": ["Flutter", "Dart"], "description": "Tracker with animations"}],
    }
    drive_doc = {
        "drive_id": "DRV_EMBEDDED_001",
        "company_name": "Semiconductor Corp",
        "drive_title": "Embedded Systems Engineer",
        "required_skills": ["C++", "RTOS", "Verilog", "Microcontrollers", "Assembly"],
        "description": "About the company: We are a global leader in chips.\nEqual opportunity employer.\nPerks: Medical insurance.\nResponsibilities: Firmware dev in C++.",
    }

    # 1. Test pruning helper
    pruned = GroqMatcherService._prune_job_description(drive_doc["description"])
    assert "Equal opportunity" not in pruned
    assert "About the company" not in pruned
    assert "Firmware dev in C++" in pruned

    # 2. Test tier 1 gatekeeper execution
    res = await GroqMatcherService.analyze_match(student_doc, drive_doc, bypass_cache=True)
    assert isinstance(res, SmartAIMatchResponse)
    assert res.source == "tier1_heuristic_filter"
    assert res.fit_level == "Needs Preparation"
    assert res.overall_match_score < 50
    assert len(res.predicted_interview_questions) <= 2
    assert len(res.critical_skill_gaps) <= 3


@pytest.mark.asyncio
async def test_multi_round_memory_and_benchmarks():
    """Verifies round progression context, role archetype adaptation, and answer benchmarks."""
    student_doc = {
        "student_id": "STU_ROUND_TEST",
        "skills": ["Python", "PyTorch", "Deep Learning", "FastAPI"],
        "deployment_skills": ["Docker", "Git"],
        "internships": [{"company_name": "AI Startup", "role_title": "ML Intern"}],
        "projects": [
            {
                "title": "Vision Transformer",
                "description": "Implemented ViT architecture for image segmentation",
                "github_url": "https://github.com/student/vit-segmentation",
            }
        ],
    }
    drive_doc = {
        "drive_id": "DRV_AI_ROLE",
        "company_name": "DeepTech AI",
        "drive_title": "AI Research Intern",
        "required_skills": ["Python", "PyTorch", "Deep Learning", "Computer Vision"],
        "description": "Looking for an AI Research Intern to build computer vision models in PyTorch.",
    }

    round_history = [
        {"round_number": 1, "result": "passed", "notes": "Solid Python and linear algebra, but verify distributed training experience."}
    ]

    res = await GroqMatcherService.analyze_match(
        student_doc=student_doc,
        drive_doc=drive_doc,
        current_round=2,
        round_history=round_history,
        bypass_cache=True,
    )

    assert isinstance(res, SmartAIMatchResponse)
    assert res.current_round == 2
    assert "AI" in res.role_archetype
    assert res.calibrated_weights["core"] == 35
    assert res.calibrated_weights["project"] == 35
    assert res.recruiter_cheat_sheet.round_focus is not None
    assert len(res.predicted_interview_questions) >= 1
    # Check that answer benchmarks are present
    for q in res.predicted_interview_questions:
        assert q.question is not None
        assert q.expected_concept is not None



