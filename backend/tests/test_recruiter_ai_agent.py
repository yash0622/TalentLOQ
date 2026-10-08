import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from app.services.recruiter_ai_agent import (
    RecruiterHybridAgent,
    clean_bot_response,
    _extract_candidate_name,
)

# ==========================================
# 1. OKF PARSER & LOGIC TESTS (BUG-01, BUG-02, CMP-01)
# ==========================================

def test_okf_bidirectional_cgpa_extraction():
    """Verify CGPA extraction works whether keyword precedes or follows number."""
    # Prefix
    okf_1 = RecruiterHybridAgent.parse_query_okf("Find candidates with CGPA >= 8.5")
    assert okf_1["min_cgpa"] == 8.5

    okf_2 = RecruiterHybridAgent.parse_query_okf("Need students with minimum 7.5 pointer")
    assert okf_2["min_cgpa"] == 7.5

    # Postfix
    okf_3 = RecruiterHybridAgent.parse_query_okf("Show me candidates having 8.0 CGPA and Python")
    assert okf_3["min_cgpa"] == 8.0

    okf_4 = RecruiterHybridAgent.parse_query_okf("Any student with 7.8+ pointer?")
    assert okf_4["min_cgpa"] == 7.8

    # Percentage conversion
    okf_5 = RecruiterHybridAgent.parse_query_okf("Students with 80 percentage")
    assert okf_5["min_cgpa"] == 8.0

    # No CGPA
    okf_none = RecruiterHybridAgent.parse_query_okf("Who knows Flutter and Dart?")
    assert okf_none["min_cgpa"] is None


def test_okf_dynamic_candidate_name_extraction():
    """Verify candidate name extraction is dynamic and not restricted to hardcoded list."""
    # Custom name via "about <Name>"
    okf_1 = RecruiterHybridAgent.parse_query_okf("Tell me about Rahul Verma")
    assert okf_1["target_name"] == "rahul verma"

    # Custom name via "candidate <Name>"
    okf_2 = RecruiterHybridAgent.parse_query_okf("What is candidate Priya's CGPA?")
    assert okf_2["target_name"] == "priya"

    # Custom name via possessive: "Aarav's skills"
    okf_3 = RecruiterHybridAgent.parse_query_okf("What are Aarav's skills?")
    assert okf_3["target_name"] == "aarav"

    # Known sample fast-path
    okf_4 = RecruiterHybridAgent.parse_query_okf("Is Chintan Sharma eligible?")
    assert "chintan" in okf_4["target_name"]


def test_okf_multiturn_follow_up_candidate_resolution():
    """Verify pronouns and follow-ups resolve candidate names from recent history."""
    history = [
        {"sender_id": "recruiter", "text": "Who is the top candidate for Flutter?"},
        {
            "sender_id": "recruiter_ai_bot",
            "text": "The top candidate is Rahul Sharma.\n\n<!-- CANDIDATE_CARDS:[{\"full_name\": \"Rahul Sharma\"}] -->",
        },
    ]

    okf = RecruiterHybridAgent.parse_query_okf("What are his projects?", conversation_history=history)
    assert okf["target_name"] == "rahul sharma"
    assert okf["is_follow_up"] is True


def test_okf_skill_and_role_extraction():
    """Verify skill taxonomy and role profile expansion."""
    okf_skills = RecruiterHybridAgent.parse_query_okf("Looking for Python, FastAPI, and Docker developers")
    assert "python" in okf_skills["target_skills"]
    assert "fastapi" in okf_skills["target_skills"]
    assert "docker" in okf_skills["target_skills"]

    okf_role = RecruiterHybridAgent.parse_query_okf("Find the best AI Engineer")
    assert okf_role["target_role"] == "ai engineer"
    assert okf_role["intent"] == "job_matching"


def test_clean_bot_response():
    """Verify chatty greetings, preambles, and follow-up prompts are stripped."""
    raw = "Hello! Great to see you again.\nRahul's CGPA is 8.9.\n\nHow would you like to proceed?"
    cleaned = clean_bot_response(raw)
    assert cleaned == "Rahul's CGPA is 8.9."

    raw2 = "Since we were just discussing candidates,\nHere is a quick refresher:\nPriya has 2 internships.\n\nWould you like me to schedule an interview?"
    cleaned2 = clean_bot_response(raw2)
    assert "Priya has 2 internships." in cleaned2
    assert "refresher" not in cleaned2.lower()
    assert "schedule an interview" not in cleaned2.lower()


# ==========================================
# 2. RAG RETRIEVAL & PROJECTION (RET-01, RET-02, PERF-01)
# ==========================================

@pytest.mark.asyncio
async def test_retrieve_rag_context_query_pushdown_and_scoring():
    """Verify OKF criteria are pushed into MongoDB query and candidate cards are enriched."""
    mock_students = [
        {
            "_id": "s-1",
            "student_id": "std-101",
            "full_name": "Test Candidate",
            "cgpa": 8.7,
            "branch": "Computer Science and Engineering",
            "graduation_year": "2026",
            "skills": ["Python", "FastAPI"],
            "coding_languages": ["Python"],
            "deployment_skills": ["Docker"],
            "internships": [{"company_name": "Tech Corp"}],
            "projects": [{"title": "RAG Chatbot"}],
            "active_backlogs": 0,
        }
    ]

    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=mock_students)

    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col):
        okf_data = {
            "target_name": None,
            "min_cgpa": 8.0,
            "target_skills": ["python", "docker"],
            "target_role": None,
            "intent": "search_candidates",
        }
        candidates = await RecruiterHybridAgent.retrieve_rag_context(okf_data)

        # Check MongoDB find query received pushdown
        called_args, called_kwargs = mock_col.find.call_args
        mongo_query = called_args[0]
        projection = called_args[1]

        assert mongo_query["cgpa"] == {"$gte": 8.0}
        assert "$or" in mongo_query
        assert "full_name" in projection
        assert "resume_pdf_base64" not in projection  # Projected out

        # Check candidate cards structure
        assert len(candidates) == 1
        cand = candidates[0]
        assert cand["full_name"] == "Test Candidate"
        assert cand["cgpa"] == 8.7
        assert cand["eligibility_status"] == "Eligible"
        assert cand["match_score"] >= 80
        assert any("Python" in r for r in cand["matched_skills"])


# ==========================================
# 3. DETERMINISTIC FALLBACK SYNTHESIZER (RES-01)
# ==========================================

def test_synthesize_fallback_response_intents():
    candidates = [
        {
            "full_name": "Aarav Patel",
            "cgpa": 8.5,
            "top_skills": ["Python", "FastAPI", "Docker"],
            "skills": ["Python", "FastAPI", "Docker", "Git"],
            "internships": [{"company_name": "Alpha Corp"}],
            "projects": [{"title": "Autonomous Agent"}],
            "backlogs": 0,
            "branch": "Information Technology",
            "graduation_year": "2026",
            "reasons": ["✓ Meets academic threshold"],
        },
        {
            "full_name": "Riya Shah",
            "cgpa": 9.1,
            "top_skills": ["Flutter", "Dart", "Firebase"],
            "skills": ["Flutter", "Dart"],
            "internships": [],
            "projects": [],
            "backlogs": 0,
            "branch": "Computer Engineering",
            "graduation_year": "2026",
            "reasons": [],
        },
    ]

    # 1. CGPA query
    res_cgpa = RecruiterHybridAgent.synthesize_fallback_response("What is Aarav's CGPA?", {"intent": "candidate_deep_dive"}, candidates)
    assert "**8.5**" in res_cgpa

    # 2. Skills query
    res_skills = RecruiterHybridAgent.synthesize_fallback_response("What are Aarav's skills?", {"intent": "candidate_deep_dive"}, candidates)
    assert "Python, FastAPI, Docker" in res_skills

    # 3. Internships query
    res_exp = RecruiterHybridAgent.synthesize_fallback_response("Does he have any internship experience?", {"intent": "candidate_deep_dive"}, candidates)
    assert "Alpha Corp" in res_exp

    # 4. Projects query
    res_proj = RecruiterHybridAgent.synthesize_fallback_response("Tell me about his projects", {"intent": "candidate_deep_dive"}, candidates)
    assert "Autonomous Agent" in res_proj

    # 5. Candidate comparison
    res_comp = RecruiterHybridAgent.synthesize_fallback_response("Compare Aarav and Riya", {"intent": "compare_candidates"}, candidates)
    assert "Aarav Patel" in res_comp and "Riya Shah" in res_comp

    # 6. Empty candidates
    res_empty = RecruiterHybridAgent.synthesize_fallback_response("Find candidates", {}, [])
    assert res_empty == "I couldn't find that information."


# ==========================================
# 4. END-TO-END ORCHESTRATION & SECURITY (SEC-01, INC-01)
# ==========================================

@pytest.mark.asyncio
async def test_process_recruiter_message_with_centralized_llm():
    """Verify prompt is delimiter-fenced, centralized LLM is called, and cards are attached."""
    mock_candidates = [
        {
            "student_id": "std-1",
            "full_name": "Chintan Sharma",
            "cgpa": 8.9,
            "branch": "Computer Science",
            "top_skills": ["Python", "FastAPI"],
            "skills": ["Python", "FastAPI"],
            "internships": [],
            "projects": [],
            "backlogs": 0,
            "match_score": 90,
            "match_title": "Software Engineer Match",
            "internship_count": 0,
        }
    ]

    mock_chat_col = MagicMock()
    mock_chat_col.find.return_value.sort.return_value.limit.return_value.to_list = AsyncMock(return_value=[])
    mock_chat_col.insert_one = AsyncMock()

    with patch("app.services.recruiter_ai_agent.get_scoped_chat_col", return_value=mock_chat_col), \
         patch.object(RecruiterHybridAgent, "retrieve_rag_context", AsyncMock(return_value=mock_candidates)), \
         patch("app.services.recruiter_ai_agent.llm_service.generate", AsyncMock(return_value={"text": "Chintan Sharma has a CGPA of 8.9."})) as mock_llm_gen:

        res = await RecruiterHybridAgent.process_recruiter_message(
            recruiter_id="rec-001",
            query="Find top candidates with Python",
            conversation_id="conv-test-123",
        )

        assert res["sender_id"] == "recruiter_ai_bot"
        assert "Chintan Sharma has a CGPA of 8.9." in res["text"]
        assert len(res["candidates"]) == 1
        assert "<!-- CANDIDATE_CARDS:" in res["text"]

        # Verify LLMService was called with delimiter-fenced prompt
        called_args, called_kwargs = mock_llm_gen.call_args
        prompt_arg = called_kwargs.get("prompt") or called_args[0]
        assert "<recruiter_query>" in prompt_arg
        assert "</recruiter_query>" in prompt_arg

        # Verify bot document was persisted
        mock_chat_col.insert_one.assert_called_once()


@pytest.mark.asyncio
async def test_process_recruiter_message_fallback_on_llm_failure():
    """Verify when centralized LLM fails or is unavailable, fallback synthesizer runs cleanly."""
    mock_candidates = [
        {
            "student_id": "std-2",
            "full_name": "Jaitra Pathak",
            "cgpa": 9.2,
            "branch": "Computer Science",
            "top_skills": ["Flutter", "Dart"],
            "skills": ["Flutter", "Dart"],
            "internships": [],
            "projects": [],
            "backlogs": 0,
            "match_score": 92,
            "match_title": "Full-Stack & Mobile Match",
            "internship_count": 0,
        }
    ]

    mock_chat_col = MagicMock()
    mock_chat_col.find.return_value.sort.return_value.limit.return_value.to_list = AsyncMock(return_value=[])
    mock_chat_col.insert_one = AsyncMock()

    with patch("app.services.recruiter_ai_agent.get_scoped_chat_col", return_value=mock_chat_col), \
         patch.object(RecruiterHybridAgent, "retrieve_rag_context", AsyncMock(return_value=mock_candidates)), \
         patch("app.services.recruiter_ai_agent.llm_service.generate", AsyncMock(side_effect=Exception("Connection timeout"))):

        res = await RecruiterHybridAgent.process_recruiter_message(
            recruiter_id="rec-001",
            query="What is Jaitra's CGPA?",
            conversation_id="conv-test-456",
        )

        # Fallback synthesizer generated direct factual response
        assert "**9.2**" in res["text"]
        assert "Jaitra Pathak" in res["text"]
        assert res["candidates"] == []  # Not a search query, cards not attached


# ==========================================
# 5. FASTEMBED VECTOR RETRIEVAL & INDEX TESTS
# ==========================================

@pytest.mark.asyncio
async def test_retrieve_rag_context_with_fastembed_vector_alignment():
    """Verify FastEmbed vector embeddings add semantic alignment boost and reason tags."""
    mock_students = [
        {
            "_id": "s-vec-1",
            "student_id": "std-vec-1",
            "full_name": "Semantic Candidate",
            "cgpa": 8.5,
            "branch": "Computer Science",
            "graduation_year": "2026",
            "skills": ["NLP", "Transformers", "PyTorch"],
            "coding_languages": ["Python"],
            "deployment_skills": ["Docker"],
            "internships": [],
            "projects": [{"title": "Dense Vector Search"}],
            "active_backlogs": 0,
        }
    ]

    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=mock_students)
    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    # Mock 384-dimensional unit vectors
    unit_vec = [0.1] * 384

    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col), \
         patch("app.services.recruiter_ai_agent.get_text_embedding_async", AsyncMock(return_value=unit_vec)):

        okf_data = {
            "target_name": None,
            "min_cgpa": None,
            "target_skills": ["nlp"],
            "target_role": None,
            "intent": "search_candidates",
            "raw_query": "Looking for candidates with deep learning and transformer experience",
        }
        candidates = await RecruiterHybridAgent.retrieve_rag_context(okf_data)

        assert len(candidates) == 1
        cand = candidates[0]
        # FastEmbed semantic boost applied
        assert any("Semantic profile alignment" in r for r in cand["reasons"])
        assert cand["match_score"] >= 75


def test_mongodb_compound_index_declared():
    """Verify MongoDB students collection compound index on (cgpa, -1) and (skills, 1) is configured."""
    import inspect
    from app.database import init_db_indexes
    src = inspect.getsource(init_db_indexes)
    assert '[("cgpa", -1), ("skills", 1)]' in src


# ==========================================
# 6. 3-TIER IMPROVEMENT SUITE (TIER 1, 2, 3)
# ==========================================

def test_tier2_domain_synonym_expansion():
    """Verify domain terms (e.g. 'frontend', 'ai', 'cloud') expand into target skills."""
    okf = RecruiterHybridAgent.parse_query_okf("Need top frontend developers")
    assert any(s in okf["target_skills"] for s in ["react", "flutter", "javascript"])

    okf_cloud = RecruiterHybridAgent.parse_query_okf("Looking for cloud engineers")
    assert any(s in okf_cloud["target_skills"] for s in ["docker", "kubernetes", "aws"])


@pytest.mark.asyncio
async def test_tier1_document_verification_trust_multiplier():
    """Verify document verification status boosts candidate score and adds trust tag."""
    mock_students = [
        {
            "_id": "s-trust-1",
            "student_id": "std-trust-1",
            "full_name": "Verified Candidate",
            "cgpa": 8.0,
            "branch": "Computer Science",
            "skills": ["Python"],
            "document_verification_status": "verified",
            "verified_credentials": {
                "github_url": {"status": "verified", "value": "https://github.com/test"}
            },
        }
    ]
    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=mock_students)
    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col):
        candidates = await RecruiterHybridAgent.retrieve_rag_context({
            "target_name": None, "min_cgpa": None, "target_skills": ["python"],
            "target_role": None, "intent": "search_candidates",
        })
        assert len(candidates) == 1
        cand = candidates[0]
        assert any("verified academic document" in r.lower() for r in cand["reasons"])
        assert any("github/linkedin" in r.lower() for r in cand["reasons"])
        assert cand["match_score"] >= 80


@pytest.mark.asyncio
async def test_tier1_precomputed_embedding_vector_priority():
    """Verify precomputed embedding_vector is used without re-embedding candidate text."""
    vec = [0.05] * 384
    mock_students = [
        {
            "_id": "s-precomputed-1",
            "student_id": "std-precomputed-1",
            "full_name": "Precomputed Candidate",
            "cgpa": 8.5,
            "branch": "Computer Science",
            "skills": ["Python", "FastAPI"],
            "embedding_vector": vec,
        }
    ]
    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=mock_students)
    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    mock_embed = AsyncMock(return_value=vec)
    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col), \
         patch("app.services.recruiter_ai_agent.get_text_embedding_async", mock_embed):
        candidates = await RecruiterHybridAgent.retrieve_rag_context({
            "target_name": None, "min_cgpa": None, "target_skills": ["python"],
            "target_role": None, "intent": "search_candidates",
            "raw_query": "Python and FastAPI specialist",
        })
        assert len(candidates) == 1
        # mock_embed should only be called ONCE (for the query), NOT for the candidate
        assert mock_embed.call_count == 1


def test_tier3_role_specific_interview_questions():
    """Verify interview question generation based on top candidate skills."""
    candidates = [{
        "full_name": "Rohit Verma",
        "cgpa": 8.8,
        "top_skills": ["Flutter", "GraphQL"],
        "match_score": 90,
    }]
    res = RecruiterHybridAgent.synthesize_fallback_response("What interview questions should I ask Rohit?", {"intent": "interview_questions"}, candidates)
    assert "Suggested interview questions for **Rohit Verma**" in res
    assert "Flutter" in res
    assert "Practical Assessment" in res


def test_tier3_candidate_comparison_matrix():
    """Verify side-by-side comparison matrix output."""
    candidates = [
        {"full_name": "Alice", "cgpa": 9.0, "top_skills": ["Python", "AWS"], "match_score": 95},
        {"full_name": "Bob", "cgpa": 8.7, "top_skills": ["React", "Node.js"], "match_score": 88},
    ]
    res = RecruiterHybridAgent.synthesize_fallback_response("Compare Alice and Bob", {"intent": "compare_candidates"}, candidates)
    assert "Candidate Comparison Matrix" in res
    assert "Alice" in res and "Bob" in res
    assert "95% Match" in res


@pytest.mark.asyncio
async def test_tier2_stream_recruiter_message_generator():
    """Verify stream_recruiter_message yields token chunks and ends with done event."""
    mock_candidates = [{
        "student_id": "std-1",
        "full_name": "Chintan Sharma",
        "cgpa": 8.9,
        "branch": "Computer Science",
        "top_skills": ["Python", "FastAPI"],
        "skills": ["Python", "FastAPI"],
        "internships": [],
        "projects": [],
        "backlogs": 0,
        "match_score": 90,
        "match_title": "Software Engineer Match",
        "internship_count": 0,
    }]
    mock_chat_col = MagicMock()
    mock_chat_col.find.return_value.sort.return_value.limit.return_value.to_list = AsyncMock(return_value=[])
    mock_chat_col.insert_one = AsyncMock()

    async def mock_gen_stream(*args, **kwargs):
        yield "Chintan "
        yield "is qualified."

    with patch("app.services.recruiter_ai_agent.get_scoped_chat_col", return_value=mock_chat_col), \
         patch.object(RecruiterHybridAgent, "retrieve_rag_context", AsyncMock(return_value=mock_candidates)), \
         patch("app.services.recruiter_ai_agent.llm_service.generate_stream", side_effect=mock_gen_stream):

        events = []
        async for ev in RecruiterHybridAgent.stream_recruiter_message("rec-1", "Who is Chintan?", "conv-stream-1"):
            events.append(ev)

        assert any("chunk" in ev and "Chintan" in ev["chunk"] for ev in events)
        done_ev = events[-1]
        assert done_ev.get("done") is True
        assert "Chintan is qualified." in done_ev["text"]
        mock_chat_col.insert_one.assert_called_once()


@pytest.mark.asyncio
async def test_chat_router_messages_stream_endpoint():
    """Verify POST /chat/messages/stream returns StreamingResponse with SSE headers."""
    from app.routers.chat import send_chat_message_stream, SendMessageRequest

    mock_user_payload = {"sub": "rec-001", "role": "recruiter"}
    req = SendMessageRequest(
        recipient_id="recruiter_ai_bot",
        text="Who is the top candidate?",
        conversation_id="conv_rec-001_recruiter_ai_bot",
    )

    async def mock_stream(*args, **kwargs):
        yield {"chunk": "Alice"}
        yield {"done": True, "id": "msg_123", "text": "Alice is top."}

    with patch("app.routers.chat.chat_messages_collection.insert_one", AsyncMock()), \
         patch("app.services.recruiter_ai_agent.recruiter_hybrid_agent.stream_recruiter_message", side_effect=mock_stream):
        resp = await send_chat_message_stream(req, user_payload=mock_user_payload)
        assert resp.media_type == "text/event-stream"
        chunks = []
        async for chunk in resp.body_iterator:
            chunks.append(chunk)
        assert any("Alice" in c for c in chunks)
        assert any('"done": true' in c for c in chunks)


@pytest.mark.asyncio
async def test_rrf_scoring_and_fusion():
    """Verify Reciprocal Rank Fusion assigns rrf_score to retrieved candidates."""
    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=[
        {"_id": "1", "student_id": "s1", "full_name": "Candidate One", "cgpa": 8.5, "skills": ["python"], "active_backlogs": 0},
        {"_id": "2", "student_id": "s2", "full_name": "Candidate Two", "cgpa": 8.0, "skills": ["python", "docker"], "active_backlogs": 0},
    ])
    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col):
        okf_data = {
            "target_name": None,
            "min_cgpa": None,
            "target_skills": ["python"],
            "target_role": None,
            "intent": "search_candidates",
            "raw_query": "Python developers",
        }
        candidates = await RecruiterHybridAgent.retrieve_rag_context(okf_data)
        assert len(candidates) == 2
        for cand in candidates:
            assert "rrf_score" in cand
            assert cand["rrf_score"] > 0.0


@pytest.mark.asyncio
async def test_micro_reranker_backlog_and_coverage_prioritization():
    """Verify micro-reranker penalizes backlogs and prioritizes skill coverage."""
    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=[
        {"_id": "1", "student_id": "s1", "full_name": "Backlog Cand", "cgpa": 9.5, "skills": ["python"], "active_backlogs": 2},
        {"_id": "2", "student_id": "s2", "full_name": "Clean Cand", "cgpa": 8.2, "skills": ["python", "fastapi"], "active_backlogs": 0},
    ])
    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col):
        okf_data = {
            "target_name": None,
            "min_cgpa": None,
            "target_skills": ["python", "fastapi"],
            "target_role": None,
            "intent": "search_candidates",
        }
        candidates = await RecruiterHybridAgent.retrieve_rag_context(okf_data)
        assert len(candidates) == 2
        # Clean Cand with full coverage and 0 backlogs must rank first
        assert candidates[0]["full_name"] == "Clean Cand"


@pytest.mark.asyncio
async def test_structured_query_llm_fallback():
    """Verify extract_structured_query_llm parses complex conditional query via LLM mock."""
    mock_llm_response = {
        "text": '{"min_cgpa": 8.2, "target_skills": ["flutter", "dart"], "target_role": "mobile developer", "intent": "search_candidates"}'
    }
    with patch("app.services.recruiter_ai_agent.llm_service.generate", AsyncMock(return_value=mock_llm_response)):
        res = await RecruiterHybridAgent.extract_structured_query_llm(
            "Looking for someone who can build flutter mobile apps with at least 8.2 pointer without backlogs"
        )
        assert res is not None
        assert res["min_cgpa"] == 8.2
        assert "flutter" in res["target_skills"]


# ==========================================
# 5. OVERHAUL SUITE: 10 REQUIRED VALIDATION TESTS
# ==========================================

@pytest.mark.asyncio
async def test_unknown_name_returns_not_found_message_and_no_cards():
    """1. Unknown name returns the not-found message and no cards."""
    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=[])  # No student found in MongoDB
    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    mock_chat_col = MagicMock()
    mock_chat_col.find.return_value.sort.return_value.limit.return_value.to_list = AsyncMock(return_value=[])
    mock_chat_col.insert_one = AsyncMock()

    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col), \
         patch("app.services.recruiter_ai_agent.get_scoped_chat_col", return_value=mock_chat_col):
        res = await RecruiterHybridAgent.process_recruiter_message("rec_1", "Tell me about Nonexistent Student", "conv_test_unknown")
        assert res["text"] == "I couldn't find that information."
        assert res["candidates"] == []
        assert "<!-- CANDIDATE_CARDS:" not in res["text"]


def test_for_backend_roles_yields_no_name():
    """2. 'for backend roles' yields no name."""
    okf = RecruiterHybridAgent.parse_query_okf("Looking for candidate for backend roles")
    assert okf["target_name"] is None
    assert okf.get("target_names") == []


def test_fresh_search_after_card_message_ignores_history_names():
    """3. Fresh search after a card message ignores history names."""
    history = [
        {"sender_id": "recruiter", "text": "Who is the top candidate for Flutter?"},
        {
            "sender_id": "recruiter_ai_bot",
            "text": "The top candidate is Rahul Sharma.\n\n<!-- CANDIDATE_CARDS:[{\"full_name\": \"Rahul Sharma\"}] -->",
        },
    ]
    # Fresh search with criteria (python, 8.0 cgpa) must not inherit "Rahul Sharma"
    okf = RecruiterHybridAgent.parse_query_okf("Show me Python developers with 8.0 CGPA", conversation_history=history)
    assert okf["target_name"] is None
    assert okf["is_follow_up"] is False
    assert "python" in okf["target_skills"]
    assert okf["min_cgpa"] == 8.0


def test_hey_show_me_top_python_devs_runs_search():
    """4. 'Hey show me top Python devs' runs a search (not greeting)."""
    okf = RecruiterHybridAgent.parse_query_okf("Hey show me top Python devs")
    assert okf["intent"] == "search_candidates"
    assert "python" in okf["target_skills"]


def test_devs_does_not_trigger_compare():
    """5. 'devs' does not trigger compare (word boundary \bvs\b prevents substring match)."""
    okf = RecruiterHybridAgent.parse_query_okf("Top backend devs")
    assert okf["intent"] != "compare_candidates"
    assert okf["intent"] == "search_candidates"


@pytest.mark.asyncio
async def test_compare_of_two_named_students_returns_both():
    """6. Compare of two named students returns both."""
    mock_students = [
        {
            "_id": "s-1",
            "student_id": "std-1",
            "full_name": "Aarav Patel",
            "cgpa": 8.5,
            "skills": ["Python"],
        },
        {
            "_id": "s-2",
            "student_id": "std-2",
            "full_name": "Priya Shah",
            "cgpa": 9.1,
            "skills": ["Flutter"],
        },
    ]
    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=mock_students)
    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col):
        okf = RecruiterHybridAgent.parse_query_okf("Compare Aarav and Priya")
        assert len(okf["target_names"]) == 2
        assert "aarav" in okf["target_names"]
        assert "priya" in okf["target_names"]

        candidates = await RecruiterHybridAgent.retrieve_rag_context(okf)
        assert len(candidates) == 2
        names = [c["full_name"] for c in candidates]
        assert "Aarav Patel" in names
        assert "Priya Shah" in names


def test_highest_cgpa_survives_clean_bot_response():
    """7. 'Highest CGPA is 9.1' survives clean_bot_response without stripping 'Hi'."""
    raw = "Highest CGPA is 9.1"
    cleaned = clean_bot_response(raw)
    assert cleaned == "Highest CGPA is 9.1"


@pytest.mark.asyncio
async def test_non_serializable_datetime_in_internships_does_not_crash():
    """8. Non-serializable datetime in internships does not crash (json default=str)."""
    from datetime import datetime
    mock_students = [
        {
            "_id": "s-dt-1",
            "student_id": "std-dt-1",
            "full_name": "Timestamp Candidate",
            "cgpa": 8.0,
            "skills": ["Python"],
            "internships": [
                {
                    "company_name": "Tech Corp",
                    "start_date": datetime(2025, 1, 15, 10, 30, 0),
                    "end_date": datetime(2025, 6, 15, 10, 30, 0),
                }
            ],
            "active_backlogs": 0,
        }
    ]
    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=mock_students)
    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    mock_chat_col = MagicMock()
    mock_chat_col.find.return_value.sort.return_value.limit.return_value.to_list = AsyncMock(return_value=[])
    mock_chat_col.insert_one = AsyncMock()

    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col), \
         patch("app.services.recruiter_ai_agent.get_scoped_chat_col", return_value=mock_chat_col):
        res = await RecruiterHybridAgent.process_recruiter_message("rec_1", "Find candidates with Python", "conv_dt_1")
        assert len(res["candidates"]) == 1
        assert res["candidates"][0]["full_name"] == "Timestamp Candidate"


@pytest.mark.asyncio
async def test_deterministic_ordering_across_runs():
    """9. Deterministic ordering across runs."""
    mock_students = [
        {"_id": f"s-{i}", "student_id": f"std-{i}", "full_name": f"Candidate {i}", "cgpa": 8.0 + (i % 3) * 0.2, "skills": ["Python", "Docker"], "active_backlogs": 0}
        for i in range(10)
    ]
    okf_data = {
        "target_names": [],
        "min_cgpa": 8.0,
        "explicit_skills": ["python", "docker"],
        "target_skills": ["python", "docker"],
        "intent": "search_candidates",
    }

    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=mock_students)
    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col):
        res1 = await RecruiterHybridAgent.retrieve_rag_context(okf_data)
        ids1 = [c["student_id"] for c in res1]

        for _ in range(5):
            res_n = await RecruiterHybridAgent.retrieve_rag_context(okf_data)
            ids_n = [c["student_id"] for c in res_n]
            assert ids1 == ids_n


@pytest.mark.asyncio
async def test_backlog_filter_works():
    """10. Backlog filter works ('no backlogs' => backlogs == 0 pushed to Mongo query)."""
    okf = RecruiterHybridAgent.parse_query_okf("Find Python devs with no backlogs")
    assert okf["max_backlogs"] == 0
    assert "python" in okf["target_skills"]

    mock_cursor = MagicMock()
    mock_cursor.limit.return_value = mock_cursor
    mock_cursor.to_list = AsyncMock(return_value=[])
    mock_col = MagicMock()
    mock_col.find.return_value = mock_cursor

    with patch("app.services.recruiter_ai_agent.get_scoped_students_col", return_value=mock_col):
        await RecruiterHybridAgent.retrieve_rag_context(okf)
        called_args, _ = mock_col.find.call_args
        mongo_query = called_args[0]
        assert "active_backlogs" in mongo_query
        assert mongo_query["active_backlogs"] == {"$lte": 0}




