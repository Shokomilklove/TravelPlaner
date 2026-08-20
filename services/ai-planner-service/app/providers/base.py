"""LLM provider interface."""
from abc import ABC, abstractmethod


class ProviderError(Exception):
    """Raised when the provider is misconfigured or the upstream call fails."""


class LLMProvider(ABC):
    name = "base"

    @property
    @abstractmethod
    def model(self):
        """Return the model identifier in use."""

    @abstractmethod
    def generate(self, system_prompt, user_prompt):
        """Return the raw text completion for the given prompts."""
