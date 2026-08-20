def test_register_and_me(client):
    resp = client.post(
        "/api/auth/register",
        json={"email": "a@b.com", "password": "password123", "full_name": "A B"},
    )
    assert resp.status_code == 201
    data = resp.get_json()
    assert "access_token" in data
    assert data["user"]["email"] == "a@b.com"

    me = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {data['access_token']}"},
    )
    assert me.status_code == 200
    assert me.get_json()["user"]["email"] == "a@b.com"


def test_register_duplicate(client):
    payload = {"email": "dup@b.com", "password": "password123", "full_name": "Dup"}
    assert client.post("/api/auth/register", json=payload).status_code == 201
    assert client.post("/api/auth/register", json=payload).status_code == 409


def test_register_validation(client):
    resp = client.post(
        "/api/auth/register",
        json={"email": "not-an-email", "password": "short", "full_name": ""},
    )
    assert resp.status_code == 400
    assert resp.get_json()["error"] == "validation_error"


def test_login_success_and_failure(client):
    client.post(
        "/api/auth/register",
        json={"email": "l@b.com", "password": "password123", "full_name": "L"},
    )
    ok = client.post("/api/auth/login", json={"email": "l@b.com", "password": "password123"})
    assert ok.status_code == 200
    assert "access_token" in ok.get_json()

    bad = client.post("/api/auth/login", json={"email": "l@b.com", "password": "wrongpass"})
    assert bad.status_code == 401


def test_me_requires_auth(client):
    assert client.get("/api/auth/me").status_code == 401
