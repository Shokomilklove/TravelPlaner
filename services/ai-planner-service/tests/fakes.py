"""Shared test doubles and fixtures data."""
import json

from app.providers.base import LLMProvider

TOKEN_HEADERS = {"X-Internal-Token": "test-internal-token"}

PLAN_REQUEST = {
    "origin": "TLV",
    "destination": "Rome",
    "start_date": "2026-08-01",
    "end_date": "2026-08-04",
    "budget": 2000,
    "currency": "USD",
    "travelers": 2,
    "preferences": {"interests": ["food", "history"]},
}

VALID_PLAN = {
    "summary": "3 days in Rome",
    "days": [
        {
            "day": 1,
            "date": "2026-08-01",
            "title": "Arrival",
            "items": [
                {"type": "activity", "title": "Evening walk", "estimated_cost": 0, "currency": "USD"}
            ],
        }
    ],
    "flights": [{"type": "flight", "title": "TLV-FCO", "estimated_cost": 300, "currency": "USD"}],
    "accommodation": [
        {"type": "accommodation", "title": "Hotel Roma", "estimated_cost": 400, "currency": "USD"}
    ],
    "activities": [
        {"type": "activity", "title": "Colosseum tour", "estimated_cost": 50, "currency": "USD"}
    ],
    "total_estimated_cost": 750,
    "currency": "USD",
}

VALID_PLAN_JSON = json.dumps(VALID_PLAN)


class FakeProvider(LLMProvider):
    """LLM provider stand-in with scripted output."""

    name = "fake"

    def __init__(self, output="", model="fake-model", raise_error=None):
        self._output = output
        self._model = model
        self._raise = raise_error
        self.calls = []

    @property
    def model(self):
        return self._model

    def generate(self, system_prompt, user_prompt):
        self.calls.append((system_prompt, user_prompt))
        if self._raise is not None:
            raise self._raise
        if isinstance(self._output, list):
            idx = min(len(self.calls) - 1, len(self._output) - 1)
            return self._output[idx]
        return self._output
