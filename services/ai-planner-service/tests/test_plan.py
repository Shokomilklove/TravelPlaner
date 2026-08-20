import json

from app.providers.base import ProviderError
from tests.fakes import PLAN_REQUEST, TOKEN_HEADERS, VALID_PLAN, VALID_PLAN_JSON, FakeProvider


def test_plan_requires_internal_token(client):
    resp = client.post("/api/plan", json=PLAN_REQUEST)
    assert resp.status_code == 401


def test_plan_rejects_wrong_token(client, app):
    app.llm_provider = FakeProvider(output=VALID_PLAN_JSON)
    resp = client.post(
        "/api/plan", json=PLAN_REQUEST, headers={"X-Internal-Token": "wrong"}
    )
    assert resp.status_code == 401


def test_plan_success(client, app):
    app.llm_provider = FakeProvider(output=VALID_PLAN_JSON, model="fake-1")
    resp = client.post("/api/plan", json=PLAN_REQUEST, headers=TOKEN_HEADERS)
    assert resp.status_code == 200, resp.get_json()
    data = resp.get_json()
    assert data["summary"] == "3 days in Rome"
    assert data["meta"] == {"provider": "fake", "model": "fake-1"}
    assert data["total_estimated_cost"] == 750
    assert data["budget_analysis"]["within_budget"] is True
    assert data["budget_analysis"]["delta"] == 1250


def test_plan_request_validation(client, app):
    app.llm_provider = FakeProvider(output=VALID_PLAN_JSON)
    resp = client.post("/api/plan", json={"origin": "TLV"}, headers=TOKEN_HEADERS)
    assert resp.status_code == 400
    assert resp.get_json()["error"] == "validation_error"


def test_plan_provider_unavailable(client, app):
    app.llm_provider = None
    resp = client.post("/api/plan", json=PLAN_REQUEST, headers=TOKEN_HEADERS)
    assert resp.status_code == 503
    assert resp.get_json()["error"] == "provider_unavailable"


def test_plan_invalid_json_retries_then_502(client, app):
    provider = FakeProvider(output="this is not json")
    app.llm_provider = provider
    resp = client.post("/api/plan", json=PLAN_REQUEST, headers=TOKEN_HEADERS)
    assert resp.status_code == 502
    # initial attempt + 1 corrective retry (AI_MAX_RETRIES=1)
    assert len(provider.calls) == 2


def test_plan_recovers_on_retry(client, app):
    provider = FakeProvider(output=["garbage", VALID_PLAN_JSON])
    app.llm_provider = provider
    resp = client.post("/api/plan", json=PLAN_REQUEST, headers=TOKEN_HEADERS)
    assert resp.status_code == 200
    assert len(provider.calls) == 2


def test_plan_handles_code_fenced_json(client, app):
    app.llm_provider = FakeProvider(output="```json\n" + VALID_PLAN_JSON + "\n```")
    resp = client.post("/api/plan", json=PLAN_REQUEST, headers=TOKEN_HEADERS)
    assert resp.status_code == 200


def test_plan_computes_total_when_missing(client, app):
    plan = dict(VALID_PLAN)
    plan.pop("total_estimated_cost")
    app.llm_provider = FakeProvider(output=json.dumps(plan))
    resp = client.post("/api/plan", json=PLAN_REQUEST, headers=TOKEN_HEADERS)
    assert resp.status_code == 200
    # 300 + 400 + 50 + 0 (day item) = 750
    assert resp.get_json()["total_estimated_cost"] == 750


def test_plan_provider_error_returns_503(client, app):
    app.llm_provider = FakeProvider(raise_error=ProviderError("upstream down"))
    resp = client.post("/api/plan", json=PLAN_REQUEST, headers=TOKEN_HEADERS)
    assert resp.status_code == 503


def test_optimize_success(client, app):
    app.llm_provider = FakeProvider(output=VALID_PLAN_JSON)
    payload = dict(PLAN_REQUEST)
    payload["current_plan"] = VALID_PLAN
    payload["goal"] = "reduce cost"
    resp = client.post("/api/optimize", json=payload, headers=TOKEN_HEADERS)
    assert resp.status_code == 200
    assert resp.get_json()["summary"] == "3 days in Rome"
