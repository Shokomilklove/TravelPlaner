import pytest

from app import create_app
from app.config import TestingConfig
from app.extensions import db as _db


@pytest.fixture
def app():
    application = create_app(TestingConfig)
    with application.app_context():
        _db.create_all()
        yield application
        _db.session.remove()
        _db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def auth(client):
    resp = client.post(
        "/api/auth/register",
        json={
            "email": "test@example.com",
            "password": "password123",
            "full_name": "Test User",
        },
    )
    assert resp.status_code == 201, resp.get_json()
    body = resp.get_json()
    return {
        "headers": {"Authorization": f"Bearer {body['access_token']}"},
        "user": body["user"],
    }
