"""Application configuration.

All settings are read from environment variables (12-factor). Sensible
development defaults are provided so the app boots without configuration,
but every secret MUST be overridden in staging/production.

Config class is selected via the ``APP_ENV`` env var:
    development | staging | production | testing
"""
import os
from datetime import timedelta
from urllib.parse import quote_plus

from sqlalchemy.pool import StaticPool


def _int(name, default):
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return int(default)


class Config:
    # --- Service metadata -------------------------------------------------
    SERVICE_NAME = "trip-service"
    SERVICE_VERSION = os.environ.get("SERVICE_VERSION", "1.0.0")

    # --- Flask ------------------------------------------------------------
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-change-me")

    # --- Database ---------------------------------------------------------
    POSTGRES_USER = quote_plus(os.environ["POSTGRES_USER"])
    POSTGRES_PASSWORD = quote_plus(os.environ["POSTGRES_PASSWORD"])
    POSTGRES_HOST = os.environ.get("POSTGRES_HOST", "postgres")
    POSTGRES_PORT = os.environ.get("POSTGRES_PORT", "5432")
    POSTGRES_DB = os.environ["POSTGRES_DB"]

    SQLALCHEMY_DATABASE_URI = (
        f"postgresql+psycopg2://{POSTGRES_USER}:{POSTGRES_PASSWORD}"
        f"@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"
    )

    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True}

    # --- Auth (JWT) -------------------------------------------------------
    JWT_SECRET_KEY = os.environ.get(
        "JWT_SECRET_KEY",
        "dev-jwt-secret-change-me",
    )
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(
        seconds=_int("JWT_ACCESS_TOKEN_EXPIRES", 86400)
    )

    # --- AI Planner (Backend B) ------------------------------------------
    AI_PLANNER_URL = os.environ.get(
        "AI_PLANNER_URL",
        "http://ai-planner-service:5002",
    )
    INTERNAL_API_TOKEN = os.environ.get(
        "INTERNAL_API_TOKEN",
        "dev-internal-token",
    )
    AI_PLANNER_TIMEOUT = float(
        os.environ.get("AI_PLANNER_TIMEOUT", "1000")
    )

    # --- HTTP / CORS ------------------------------------------------------
    CORS_ORIGINS = os.environ.get("CORS_ORIGINS", "*")

    # --- Logging ----------------------------------------------------------
    LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

    DEBUG = False
    TESTING = False


class DevelopmentConfig(Config):
    DEBUG = True


class StagingConfig(Config):
    DEBUG = False


class ProductionConfig(Config):
    DEBUG = False


class TestingConfig(Config):
    TESTING = True
    DEBUG = True

    # In-memory SQLite shared across the app via a single connection
    # so the test suite needs no PostgreSQL instance.
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "TEST_DATABASE_URL",
        "sqlite://",
    )
    SQLALCHEMY_ENGINE_OPTIONS = {
        "connect_args": {"check_same_thread": False},
        "poolclass": StaticPool,
    }

    SECRET_KEY = "test-secret"
    JWT_SECRET_KEY = "test-jwt-secret"
    AI_PLANNER_URL = "http://ai-planner.test"
    INTERNAL_API_TOKEN = "test-internal-token"


CONFIG_MAP = {
    "development": DevelopmentConfig,
    "staging": StagingConfig,
    "production": ProductionConfig,
    "testing": TestingConfig,
}


def get_config():
    env = os.environ.get("APP_ENV", "development").strip().lower()
    return CONFIG_MAP.get(env, DevelopmentConfig)
