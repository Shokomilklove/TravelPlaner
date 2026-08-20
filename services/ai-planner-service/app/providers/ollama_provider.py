"""Ollama (self-hosted) chat provider."""
from app.providers.base import LLMProvider, ProviderError


class OllamaProvider(LLMProvider):
    name = "ollama"

    def __init__(self, base_url, model, timeout=90.0, temperature=0.7):
        self.base_url = base_url.rstrip("/")
        self._model = model
        self.timeout = timeout
        self.temperature = temperature

    @property
    def model(self):
        return self._model

    def generate(self, system_prompt, user_prompt):
        import httpx

        payload = {
            "model": self._model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "stream": False,
            "format": "json",
            "options": {"temperature": self.temperature},
        }
        try:
            resp = httpx.post(
                f"{self.base_url}/api/chat", json=payload, timeout=self.timeout
            )
            resp.raise_for_status()
            data = resp.json()
        except httpx.HTTPError as exc:
            raise ProviderError(f"Ollama request failed: {exc}") from exc
        return (data.get("message") or {}).get("content", "")
