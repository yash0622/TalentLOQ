import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from app.services.autonomous_placement_agent import AutonomousPlacementAgent
from app.services.ai_bot_assistant import AiBotAssistant


@pytest.fixture
def sample_ai_student():
    return {
        "student_id": "STU_AI_001",
        "user_id": "USR_AI_001",
        "full_name": "Test AI Student",
        "CGPA": 8.5,
        "active_backlogs": 0,
        "branch": "CSE",
        "has_resume": True,
        "skills": ["Python", "PyTorch", "TensorFlow", "FastAPI"],
        "career_preferences": {
            "target_roles": ["AI/ML Engineer", "Data Scientist"],
            "preferred_domains": ["AI/ML", "Deep Learning"],
            "min_ctc_lpa": 3.0,
            "max_ctc_lpa": 4.0,
            "auto_apply_enabled": True,
            "notify_on_ineligible_match": True,
        },
        "preferences_vector": [0.1] * 384,
    }


@pytest.fixture
def sample_ai_drive():
    return {
        "drive_id": "DRV_AI_001",
        "company_name": "DeepTech AI",
        "drive_title": "AI/ML Engineer",
        "description": "Looking for Deep Learning and Python engineers.",
        "min_cgpa": 7.0,
        "max_allowed_backlogs": 0,
        "eligible_courses": ["CSE", "ALL"],
        "ctc_min": 3.5,
        "ctc_max": 4.0,
        "required_skills": ["Python", "PyTorch"],
        "status": "published",
        "jd_vector": [0.1] * 384,
    }


@pytest.mark.asyncio
async def test_agent_auto_applies_and_sends_bot_chat(sample_ai_student, sample_ai_drive):
    with patch("app.services.autonomous_placement_agent.applications_collection") as mock_apps, \
         patch("app.services.autonomous_placement_agent.drives_collection") as mock_drives, \
         patch("app.services.autonomous_placement_agent.notifications_collection") as mock_notifs, \
         patch("app.services.ai_bot_assistant.ai_bot_assistant.send_agent_notification_message", new_callable=AsyncMock) as mock_bot, \
         patch("app.services.autonomous_placement_agent.log_agent_decision", new_callable=AsyncMock) as mock_log:

        mock_apps.find_one = AsyncMock(return_value=None)
        mock_apps.insert_one = AsyncMock(return_value=MagicMock())
        mock_drives.update_many = AsyncMock()
        mock_notifs.insert_one = AsyncMock(return_value=MagicMock())

        res = await AutonomousPlacementAgent.evaluate_and_act(sample_ai_student, sample_ai_drive)

        assert res is not None
        assert res["action"] == "AUTO_APPLIED"

        # Verify application inserted
        mock_apps.insert_one.assert_called_once()
        inserted_app = mock_apps.insert_one.call_args[0][0]
        assert inserted_app["drive_id"] == "DRV_AI_001"
        assert inserted_app["student_id"] == "STU_AI_001"
        assert inserted_app["application_source"] == "AGENTIC_AUTO_APPLY"

        # Verify bot sent natural language message into chat thread
        mock_bot.assert_called_once()
        bot_args = mock_bot.call_args[0]
        assert bot_args[0] == "USR_AI_001"
        assert "DeepTech AI has been added" in bot_args[1]
        assert "submitted your application" in bot_args[1]


@pytest.mark.asyncio
async def test_agent_notifies_bot_when_ineligible_due_to_cgpa(sample_ai_student, sample_ai_drive):
    # Student has CGPA 6.5, but drive requires 7.0
    sample_ai_student["CGPA"] = 6.5

    with patch("app.services.autonomous_placement_agent.applications_collection") as mock_apps, \
         patch("app.services.autonomous_placement_agent.notifications_collection") as mock_notifs, \
         patch("app.services.ai_bot_assistant.ai_bot_assistant.send_agent_notification_message", new_callable=AsyncMock) as mock_bot, \
         patch("app.services.autonomous_placement_agent.log_agent_decision", new_callable=AsyncMock) as mock_log:

        mock_apps.find_one = AsyncMock(return_value=None)
        mock_notifs.insert_one = AsyncMock(return_value=MagicMock())

        res = await AutonomousPlacementAgent.evaluate_and_act(sample_ai_student, sample_ai_drive)

        assert res is not None
        assert res["action"] == "INELIGIBLE_NOTIFIED"
        assert any("CGPA" in b for b in res["barriers"])

        # Must NOT create application
        mock_apps.insert_one.assert_not_called()

        # Must send natural-language reason to AI Bot chat thread
        mock_bot.assert_called_once()
        bot_args = mock_bot.call_args[0]
        assert "did not apply because" in bot_args[1]
        assert "CGPA" in bot_args[1]


@pytest.mark.asyncio
async def test_agent_nudges_when_auto_apply_disabled(sample_ai_student, sample_ai_drive):
    sample_ai_student["career_preferences"]["auto_apply_enabled"] = False

    with patch("app.services.autonomous_placement_agent.applications_collection") as mock_apps, \
         patch("app.services.autonomous_placement_agent.notifications_collection") as mock_notifs, \
         patch("app.services.ai_bot_assistant.ai_bot_assistant.send_agent_notification_message", new_callable=AsyncMock) as mock_bot:

        mock_apps.find_one = AsyncMock(return_value=None)
        mock_notifs.insert_one = AsyncMock(return_value=MagicMock())

        res = await AutonomousPlacementAgent.evaluate_and_act(sample_ai_student, sample_ai_drive)

        assert res is not None
        assert res["action"] == "NUDGED_FOR_MANUAL_APPLY"
        mock_apps.insert_one.assert_not_called()
        mock_bot.assert_called_once()


def test_ai_bot_parses_natural_language_instruction(sample_ai_student):
    prompt = "Apply for upcoming companies that require AI/ML skills or other domains mentioned in my resume, with a salary package of 3–4 LPA."
    parsed = AiBotAssistant.parse_instruction(prompt, sample_ai_student)

    assert parsed["auto_apply_enabled"] is True
    assert any("AI/ML" in r for r in parsed["target_roles"])
    assert parsed["min_ctc_lpa"] == 3.0
    assert parsed["max_ctc_lpa"] == 4.0

    # Test confirmation generation
    reply = AiBotAssistant.generate_bot_reply(parsed, sample_ai_student)
    assert "3.0–4.0 LPA" in reply or "3–4 LPA" in reply
    assert "Autonomous Auto-Apply" in reply


@pytest.mark.asyncio
async def test_agent_notifies_when_salary_below_requested_range(sample_ai_student, sample_ai_drive):
    # Student wants at least 5.0 LPA, drive offers 4.5 LPA
    sample_ai_student["career_preferences"]["min_ctc_lpa"] = 5.0
    sample_ai_student["career_preferences"]["max_ctc_lpa"] = 6.0
    sample_ai_drive["ctc_min"] = 4.5
    sample_ai_drive["ctc_max"] = 4.5

    with patch("app.services.autonomous_placement_agent.applications_collection") as mock_apps, \
         patch("app.services.autonomous_placement_agent.log_agent_decision", new_callable=AsyncMock), \
         patch("app.services.ai_bot_assistant.ai_bot_assistant.send_agent_notification_message", new_callable=AsyncMock) as mock_bot:

        mock_apps.find_one = AsyncMock(return_value=None)

        res = await AutonomousPlacementAgent.evaluate_and_act(sample_ai_student, sample_ai_drive)

        assert res is not None
        assert res["action"] == "SALARY_BELOW_RANGE"
        mock_apps.insert_one.assert_not_called()
        mock_bot.assert_called_once()
        bot_args = mock_bot.call_args[0]
        # E.g. "DeepTech AI has been added, but I did not apply because the offered salary is 4.5 LPA, which is below your requested 5.0–6.0 LPA range."
        assert "below your requested" in bot_args[1]
        assert "4.5 LPA" in bot_args[1]


@pytest.mark.asyncio
async def test_agent_skips_blacklisted_company(sample_ai_student, sample_ai_drive):
    sample_ai_student["career_preferences"]["blacklisted_companies"] = ["DeepTech AI"]

    with patch("app.services.autonomous_placement_agent.applications_collection") as mock_apps, \
         patch("app.services.ai_bot_assistant.ai_bot_assistant.send_agent_notification_message", new_callable=AsyncMock) as mock_bot:

        mock_apps.find_one = AsyncMock(return_value=None)

        # Path 1: matches_career_preferences
        match, reason, _ = AutonomousPlacementAgent.matches_career_preferences(sample_ai_student, sample_ai_drive)
        assert match is False
        assert reason == "COMPANY_BLACKLISTED"

        # Path 2: evaluate_and_act
        res = await AutonomousPlacementAgent.evaluate_and_act(sample_ai_student, sample_ai_drive)
        assert res is None
        mock_apps.insert_one.assert_not_called()
        mock_bot.assert_not_called()


@pytest.mark.asyncio
async def test_agent_deduplicates_salary_below_range_alert(sample_ai_student, sample_ai_drive):
    sample_ai_student["career_preferences"]["min_ctc_lpa"] = 5.0
    sample_ai_student["career_preferences"]["max_ctc_lpa"] = 6.0
    sample_ai_drive["ctc_min"] = 4.5
    sample_ai_drive["ctc_max"] = 4.5

    with patch("app.services.autonomous_placement_agent.applications_collection") as mock_apps, \
         patch("app.services.autonomous_placement_agent.agent_runs_collection") as mock_agent_runs, \
         patch("app.services.autonomous_placement_agent.log_agent_decision", new_callable=AsyncMock), \
         patch("app.services.ai_bot_assistant.ai_bot_assistant.send_agent_notification_message", new_callable=AsyncMock) as mock_bot:

        mock_apps.find_one = AsyncMock(return_value=None)
        # First call: no prior decision exists
        mock_agent_runs.find_one = AsyncMock(return_value=None)
        mock_agent_runs.update_one = AsyncMock(return_value=MagicMock(matched_count=0))

        res1 = await AutonomousPlacementAgent.evaluate_and_act(sample_ai_student, sample_ai_drive)
        assert res1 is not None
        assert res1["action"] == "SALARY_BELOW_RANGE"
        assert mock_bot.call_count == 1

        # Second call: decision already exists in agent_runs
        mock_agent_runs.find_one = AsyncMock(return_value={"_id": "existing"})
        mock_agent_runs.update_one = AsyncMock(return_value=MagicMock(matched_count=1))

        res2 = await AutonomousPlacementAgent.evaluate_and_act(sample_ai_student, sample_ai_drive)
        assert res2 is not None
        assert res2["action"] == "SALARY_BELOW_RANGE"
        # Notification must NOT be sent again
        assert mock_bot.call_count == 1


@pytest.mark.asyncio
async def test_ai_bot_view_criteria_returns_stored_without_writing(sample_ai_student):
    with patch("app.services.ai_bot_assistant.students_collection") as mock_students, \
         patch("app.services.ai_bot_assistant.chat_messages_collection") as mock_chat:

        mock_students.find_one = AsyncMock(return_value=sample_ai_student)
        mock_students.update_one = AsyncMock()
        mock_chat.insert_one = AsyncMock()

        reply = await AiBotAssistant.process_student_message("USR_AI_001", "show my criteria", "conv_123")

        assert "Target Roles: AI/ML Engineer, Data Scientist" in reply
        assert "Autonomous Auto-Apply Enabled" in reply
        # Must NOT update student preferences or trigger applications
        mock_students.update_one.assert_not_called()
        mock_chat.insert_one.assert_called_once()

