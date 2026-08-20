"""Selects and constructs the configured LLM provider."""
from app.providers.base import ProviderError


def build_provider(config):
    provider = (config.get("AI_PROVIDER") or "openai").lower()

    if provider == "openai":
        from app.providers.openai_provider import OpenAIProvider

        return OpenAIProvider(
            api_key=config.get("OPENAI_API_KEY", ""),
            model=config.get("OPENAI_MODEL", "gpt-4o-mini"),
            base_url=config.get("OPENAI_BASE_URL"),
            timeout=config.get("AI_TIMEOUT", 90.0),
            temperature=config.get("AI_TEMPERATURE", 0.7),
        )

    if provider == "ollama":
        from app.providers.ollama_provider import OllamaProvider

        return OllamaProvider(
            base_url=config.get("OLLAMA_URL", "http://localhost:11434"),
            model=config.get("OLLAMA_MODEL", "llama3.1"),
            timeout=config.get("AI_TIMEOUT", 90.0),
            temperature=config.get("AI_TEMPERATURE", 0.7),
        )

    raise ProviderError(f"Unknown AI_PROVIDER: {provider!r} (expected 'openai' or 'ollama')")
