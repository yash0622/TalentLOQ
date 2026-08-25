"""End-to-end API proofs for the student/recruiter application visibility flow."""

from unittest.mock import AsyncMock, MagicMock

import pytest
from httpx import ASGITransport, AsyncClient

from app.jwt_utils import create_access_token
from app.main import app


class _Cursor:
    def __init__(self, values):
        self.values = values

    def sort(self, *_args, **_kwargs):
        return self

    def skip(self, count):
        self.values = self.values[count:]
        return self

    def limit(self, count):
        self.values = self.values[:count]
        return self

    async def to_list(self, length=None):
        return list(self.values if length is None else self.values[:length])


def _matching(document, query):
    return all(document.get(key) == value for key, value in query.items())


def _setup_visibility_store(monkeypatch):
    import app.routers.drives_recruiter as recruiter_router
    import app.routers.drives_student as student_router

    drives = {}
    applications = []
    students = {}

    async def find_drive(query):
        return next((d for d in drives.values() if _matching(d, query)), None)

    async def count_drives(query):
        return sum(1 for d in drives.values() if _matching(d, query))

    def find_drives(query):
        return _Cursor([d for d in drives.values() if _matching(d, query)])

    async def find_application(query):
        return next((a for a in applications if _matching(a, query)), None)

    async def count_applications(query):
        return sum(1 for a in applications if _matching(a, query))

    def find_applications(query):
        return _Cursor([a for a in applications if _matching(a, query)])

    async def insert_application(document):
        if any(a["student_id"] == document["student_id"] and a["drive_id"] == document["drive_id"] for a in applications):
            from pymongo.errors import DuplicateKeyError
            raise DuplicateKeyError("unique_student_drive_application")
        applications.append(dict(document))
        return MagicMock(inserted_id=document["app_id"])

    def aggregate_applications(pipeline):
        drive_ids = pipeline[0]["$match"]["drive_id"]["$in"]
        rows = []
        for drive_id in drive_ids:
            matching = [a for a in applications if a.get("drive_id") == drive_id]
            if matching:
                rows.append({
                    "_id": drive_id,
                    "applicant_count": len(matching),
                    "eligible_applicant_count": sum(1 for a in matching if a.get("is_eligible") is True),
                })
        return _Cursor(rows)

    async def find_student(query):
        sid = query.get("student_id") or query.get("user_id")
        return students.get(sid)

    for router in (student_router, recruiter_router):
        monkeypatch.setattr(router.drives_collection, "find_one", find_drive)
        monkeypatch.setattr(router.drives_collection, "find", find_drives)
        monkeypatch.setattr(router.drives_collection, "count_documents", count_drives)
        monkeypatch.setattr(router.applications_collection, "find_one", find_application)
        monkeypatch.setattr(router.applications_collection, "find", find_applications)
        monkeypatch.setattr(router.applications_collection, "count_documents", count_applications)
        monkeypatch.setattr(router.students_collection, "find_one", find_student)
        monkeypatch.setattr(router.users_collection, "find_one", find_student)
        monkeypatch.setattr(router.audit_logs_collection, "insert_one", AsyncMock())
    monkeypatch.setattr(student_router.applications_collection, "insert_one", insert_application)
    monkeypatch.setattr(recruiter_router.applications_collection, "aggregate", aggregate_applications)

    drives["drive-visibility"] = {
        "drive_id": "drive-visibility",
        "company_name": "Visibility Labs",
        "drive_title": "Platform Engineer",
        "status": "published",
        "min_cgpa": 6.0,
        "selection_process": [],
    }
    return drives, applications, students


def _token(student_id):
    return create_access_token(user_id=student_id, role="student")


def _recruiter_headers():
    return {"Authorization": f"Bearer {create_access_token(user_id='recruiter-1', role='recruiter')}"}


@pytest.mark.asyncio
async def test_apply_creates_application_visible_to_both_sides(monkeypatch):
    _, _, students = _setup_visibility_store(monkeypatch)
    students["student-a"] = {"student_id": "student-a", "has_resume": True, "CGPA": 8.5}
    student_headers = {"Authorization": f"Bearer {_token('student-a')}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        applied = await client.post("/drives/drive-visibility/apply", headers=student_headers)
        assert applied.status_code == 201
        assert applied.json()["application"]["status"] == "applied"

        detail = await client.get("/drives/drive-visibility", headers=student_headers)
        assert detail.json()["has_applied"] is True
        assert detail.json()["my_application_status"] == "applied"

        applicants = await client.get("/recruiter/drives/drive-visibility/applicants", headers=_recruiter_headers())
        assert [item["student_id"] for item in applicants.json()["items"]] == ["student-a"]

        drives = await client.get("/recruiter/drives", headers=_recruiter_headers())
        item = next(item for item in drives.json()["items"] if item["drive_id"] == "drive-visibility")
        assert item["applicant_count"] == 1


@pytest.mark.asyncio
async def test_duplicate_apply_rejected(monkeypatch):
    _, applications, students = _setup_visibility_store(monkeypatch)
    students["student-a"] = {"student_id": "student-a", "has_resume": True, "CGPA": 8.5}
    headers = {"Authorization": f"Bearer {_token('student-a')}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        assert (await client.post("/drives/drive-visibility/apply", headers=headers)).status_code == 201
        before = len(applications)
        duplicate = await client.post("/drives/drive-visibility/apply", headers=headers)
        assert duplicate.status_code == 409
        assert len(applications) == before


@pytest.mark.asyncio
async def test_applicant_count_matches_actual_applications(monkeypatch):
    _, applications, students = _setup_visibility_store(monkeypatch)
    ids = ["student-a", "student-b", "student-c"]
    for sid in ids:
        students[sid] = {"student_id": sid, "has_resume": True, "CGPA": 8.5}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        for sid in ids:
            response = await client.post(
                "/drives/drive-visibility/apply",
                headers={"Authorization": f"Bearer {_token(sid)}"},
            )
            assert response.status_code == 201
        drives = await client.get("/recruiter/drives", headers=_recruiter_headers())
        item = drives.json()["items"][0]
        assert item["applicant_count"] == len(applications) == 3
        applicants = await client.get("/recruiter/drives/drive-visibility/applicants", headers=_recruiter_headers())
        assert {a["student_id"] for a in applicants.json()["items"]} == set(ids)


@pytest.mark.asyncio
async def test_other_students_cannot_see_each_others_applied_status(monkeypatch):
    _, _, students = _setup_visibility_store(monkeypatch)
    for sid in ("student-a", "student-b"):
        students[sid] = {"student_id": sid, "has_resume": True, "CGPA": 8.5}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        assert (await client.post("/drives/drive-visibility/apply", headers={"Authorization": f"Bearer {_token('student-a')}"})).status_code == 201
        detail_b = await client.get("/drives/drive-visibility", headers={"Authorization": f"Bearer {_token('student-b')}"})
        assert detail_b.json()["has_applied"] is False
        assert detail_b.json()["my_application_status"] is None


@pytest.mark.asyncio
async def test_recruiter_view_reflects_immediately_after_apply(monkeypatch):
    _, _, students = _setup_visibility_store(monkeypatch)
    students["student-a"] = {"student_id": "student-a", "has_resume": True, "CGPA": 8.5}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        await client.post("/drives/drive-visibility/apply", headers={"Authorization": f"Bearer {_token('student-a')}"})
        applicants = await client.get("/recruiter/drives/drive-visibility/applicants", headers=_recruiter_headers())
        assert applicants.status_code == 200
        assert applicants.json()["items"][0]["student_id"] == "student-a"
