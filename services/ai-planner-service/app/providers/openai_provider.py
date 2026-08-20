"""OpenAI (and OpenAI-compatible) chat-completions provider."""
from app.providers.base import LLMProvider, ProviderError


class OpenAIProvider(LLMProvider):
    name = "openai"

    def __init__(self, api_key, model, base_url=None, timeout=90.0, temperature=0.7):
        if not api_key:
            raise ProviderError("OPENAI_API_KEY is not configured")
        # Imported lazily so the service can start even if the package is absent
        # when a different provider is selected.
        from openai import OpenAI

        self._client = OpenAI(api_key=api_key, base_url=base_url, timeout=timeout)
        self._model = model
        self.temperature = temperature

    @property
    def model(self):
        return self._model

    def generate(self, system_prompt, user_prompt):
        try:
            resp = self._client.chat.completions.create(
                model=self._model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                temperature=self.temperature,
                response_format={"type": "json_object"},
            )
            return resp.choices[0].message.content or ""
        except Exception as exc:  # openai raises many subclasses
            raise ProviderError(f"OpenAI request failed: {exc}") from exc
