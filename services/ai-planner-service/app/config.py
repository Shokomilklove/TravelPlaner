"""AI Planner Service configuration.

Configuration values are loaded from environment variables and .env.
Config class selected via APP_ENV: development | staging | production | testing
"""

import os

from dotenv import load_dotenv

# Load .env from the ai-planner-service project directory.
load_dotenv()


class Config:
    SERVICE_NAME = "ai-planner-service"
    SERVICE_VERSION = os.environ.get("SERVICE_VERSION", "1.0.0")

    # Shared secret required on every request (set by Trip Service).
    INTERNAL_API_TOKEN = os.environ.get(
        "INTERNAL_API_TOKEN",
        "dev-internal-token",
    )

    # Which LLM backend to use: "openai" or "ollama".
    AI_PROVIDER = os.environ.get("AI_PROVIDER", "openai").lower()

    # --- OpenAI ---
    OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
    OPENAI_MODEL = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    OPENAI_BASE_URL = os.environ.get("OPENAI_BASE_URL") or None

    # --- Ollama ---
    OLLAMA_URL = os.environ.get(
        "OLLAMA_URL",
        "http://localhost:11434",
    )
    OLLAMA_MODEL = os.environ.get(
        "OLLAMA_MODEL",
        "llama3.1",
    )

    # --- Generation tuning ---
    AI_TIMEOUT = float(
        os.environ.get("AI_TIMEOUT", "90")
    )

    AI_TEMPERATURE = float(
        os.environ.get("AI_TEMPERATURE", "0.7")
    )

    AI_MAX_RETRIES = int(
        os.environ.get("AI_MAX_RETRIES", "1")
    )

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
    INTERNAL_API_TOKEN = "test-internal-token"
    AI_PROVIDER = "openai"
    OPENAI_API_KEY = "test-key"
    AI_MAX_RETRIES = 1


CONFIG_MAP = {
    "development": DevelopmentConfig,
    "staging": StagingConfig,
    "production": ProductionConfig,
    "testing": TestingConfig,
}


def get_config():
    env = os.environ.get("APP_ENV", "development").strip().lower()
    return CONFIG_MAP.get(env, DevelopmentConfig)

