from app.prompt_builder import build_prompt
from tests.fakes import PLAN_REQUEST


def test_build_prompt_includes_trip_details():
    system, user = build_prompt(PLAN_REQUEST)
    assert "travel planner" in system.lower()
    assert "Rome" in user
    assert "TLV" in user
    assert "2026-08-01" in user
    assert "JSON" in user


def test_build_prompt_with_budget():
    system, user = build_prompt(PLAN_REQUEST)
    assert "2000" in user


def test_build_prompt_without_budget():
    req = dict(PLAN_REQUEST)
    req["budget"] = None
    _, user = build_prompt(req)
    assert "No fixed budget" in user


def test_build_prompt_extra_instructions():
    _, user = build_prompt(PLAN_REQUEST, extra_instructions="OPTIMIZE THIS")
    assert "OPTIMIZE THIS" in user
