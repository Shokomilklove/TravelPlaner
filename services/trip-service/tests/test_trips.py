import datetime

from app.clients.ai_planner import AIPlannerError


def _trip_payload(**overrides):
    today = datetime.date.today()
    payload = {
        "origin": "TLV",
        "destination": "Rome",
        "start_date": today.isoformat(),
        "end_date": (today + datetime.timedelta(days=4)).isoformat(),
        "budget_amount": 2000,
        "budget_currency": "USD",
        "travelers": 2,
        "preferences": {"interests": ["food", "history"]},
    }
    payload.update(overrides)
    return payload


def _create_trip(client, headers, **overrides):
    resp = client.post("/api/trips", json=_trip_payload(**overrides), headers=headers)
    assert resp.status_code == 201, resp.get_json()
    return resp.get_json()["trip"]


def test_create_and_list_trip(client, auth):
    trip = _create_trip(client, auth["headers"])
    assert trip["destination"] == "Rome"
    assert trip["status"] == "draft"

    listing = client.get("/api/trips", headers=auth["headers"])
    assert listing.status_code == 200
    assert len(listing.get_json()["trips"]) == 1


def test_trips_require_auth(client):
    assert client.get("/api/trips").status_code == 401


def test_end_date_before_start_date_rejected(client, auth):
    today = datetime.date.today()
    resp = client.post(
        "/api/trips",
        json=_trip_payload(
            start_date=today.isoformat(),
            end_date=(today - datetime.timedelta(days=1)).isoformat(),
        ),
        headers=auth["headers"],
    )
    assert resp.status_code == 400


def test_update_and_delete_trip(client, auth):
    trip = _create_trip(client, auth["headers"])

    updated = client.put(
        f"/api/trips/{trip['id']}",
        json={"title": "New Title"},
        headers=auth["headers"],
    )
    assert updated.status_code == 200
    assert updated.get_json()["trip"]["title"] == "New Title"

    deleted = client.delete(f"/api/trips/{trip['id']}", headers=auth["headers"])
    assert deleted.status_code == 204
    assert client.get(f"/api/trips/{trip['id']}", headers=auth["headers"]).status_code == 404


def test_save_and_unsave_trip(client, auth):
    trip = _create_trip(client, auth["headers"])

    saved = client.post(f"/api/trips/{trip['id']}/save", headers=auth["headers"])
    assert saved.status_code == 200
    assert saved.get_json()["trip"]["is_saved"] is True

    saved_list = client.get("/api/trips?saved=true", headers=auth["headers"])
    assert len(saved_list.get_json()["trips"]) == 1

    unsaved = client.post(f"/api/trips/{trip['id']}/unsave", headers=auth["headers"])
    assert unsaved.get_json()["trip"]["is_saved"] is False


def test_users_cannot_access_others_trips(client, auth):
    trip = _create_trip(client, auth["headers"])

    other = client.post(
        "/api/auth/register",
        json={"email": "other@b.com", "password": "password123", "full_name": "Other"},
    ).get_json()
    other_headers = {"Authorization": f"Bearer {other['access_token']}"}

    assert client.get(f"/api/trips/{trip['id']}", headers=other_headers).status_code == 404
    assert client.delete(f"/api/trips/{trip['id']}", headers=other_headers).status_code == 404


class _FakePlanner:
    def plan(self, payload):
        return {
            "summary": "4 days in Rome",
            "days": [{"day": 1, "date": payload["start_date"], "items": []}],
            "flights": [{"title": "TLV to FCO", "estimated_cost": 300}],
            "accommodation": [{"title": "Hotel Roma", "estimated_cost": 400}],
            "activities": [{"title": "Colosseum", "estimated_cost": 50}],
            "total_estimated_cost": 1500,
            "currency": "USD",
            "budget_analysis": {"within_budget": True, "delta": 500, "suggestions": []},
            "meta": {"provider": "mock", "model": "test-model"},
        }

    def health(self):
        return True


class _FailingPlanner:
    def plan(self, payload):
        raise AIPlannerError("AI Planner unreachable", 503)

    def health(self):
        return False


def test_plan_trip_success(client, auth, app):
    app.ai_planner_client = _FakePlanner()
    trip = _create_trip(client, auth["headers"])

    resp = client.post(f"/api/trips/{trip['id']}/plan", headers=auth["headers"])
    assert resp.status_code == 201, resp.get_json()
    itinerary = resp.get_json()["itinerary"]
    assert itinerary["summary"] == "4 days in Rome"
    assert itinerary["provider"] == "mock"
    assert itinerary["total_estimated_cost"] == 1500

    fetched = client.get(f"/api/trips/{trip['id']}", headers=auth["headers"]).get_json()["trip"]
    assert fetched["status"] == "planned"
    assert fetched["itinerary"]["summary"] == "4 days in Rome"


def test_plan_trip_propagates_ai_error(client, auth, app):
    app.ai_planner_client = _FailingPlanner()
    trip = _create_trip(client, auth["headers"])

    resp = client.post(f"/api/trips/{trip['id']}/plan", headers=auth["headers"])
    assert resp.status_code == 503
    assert resp.get_json()["error"] == "ai_planner_error"
