class _HealthyPlanner:
    def health(self):
        return True


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["status"] == "ok"
    assert body["service"] == "trip-service"


def test_ready(client):
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ready"


def test_metrics_endpoint(client):
    client.get("/health")  # generate some traffic first
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert b"http_requests_total" in resp.data


def test_service_registry(client, app):
    app.ai_planner_client = _HealthyPlanner()
    resp = client.get("/api/services")
    assert resp.status_code == 200
    services = {s["name"]: s for s in resp.get_json()["services"]}
    assert "trip-service" in services
    assert services["ai-planner-service"]["status"] == "healthy"
