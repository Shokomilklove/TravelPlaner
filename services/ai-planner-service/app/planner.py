"""Trip planning orchestration: prompt -> LLM -> parse/validate -> budget."""
import json

from pydantic import ValidationError

from app.budget import analyze_budget
from app.prompt_builder import build_prompt
from app.providers.base import ProviderError
from app.schemas import LLMPlan


class PlanningError(Exception):
    def __init__(self, message, status_code=502):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def generate_plan(provider, req, max_retries=1, extra_instructions=None):
    """Generate a validated, budget-annotated plan dict.

    Retries once (by default) with a corrective nudge if the model returns
    JSON that does not parse/validate. Raises ``PlanningError`` on failure.
    """
    system_prompt, base_user_prompt = build_prompt(req, extra_instructions)
    user_prompt = base_user_prompt

    for attempt in range(max_retries + 1):
        try:
            raw = provider.generate(system_prompt, user_prompt)
        except ProviderError as exc:
            # Provider unreachable / misconfigured -> upstream unavailable.
            raise PlanningError(str(exc), 503) from exc

        plan = _parse_plan(raw)
        if plan is not None:
            return _finalize(plan, req, provider)

        # Nudge the model to fix its output on the next attempt.
        user_prompt = (
            base_user_prompt
            + "\n\nIMPORTANT: your previous response was not valid JSON matching "
            "the schema. Respond again with ONLY a valid JSON object."
        )

    raise PlanningError(
        "The AI response could not be parsed into the expected schema", 502
    )


def _parse_plan(raw):
    text = _extract_json(raw)
    if not text:
        return None
    try:
        data = json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return None
    try:
        return LLMPlan.model_validate(data)
    except ValidationError:
        return None


def _extract_json(raw):
    if not raw:
        return ""
    text = raw.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text[:4].lower() == "json":
            text = text[4:]
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return text[start : end + 1]
    return text


def _sum_costs(plan):
    total = 0.0
    for item in plan.flights + plan.accommodation + plan.activities:
        total += item.estimated_cost or 0.0
    for day in plan.days:
        for item in day.items:
            total += item.estimated_cost or 0.0
    return total


def _finalize(plan, req, provider):
    currency = plan.currency or req.get("currency") or "USD"
    total = plan.total_estimated_cost
    if total is None or total <= 0:
        total = _sum_costs(plan)

    result = plan.model_dump()
    result["currency"] = currency
    result["total_estimated_cost"] = round(float(total), 2)
    result["budget_analysis"] = analyze_budget(total, req.get("budget"), currency)
    result["meta"] = {"provider": provider.name, "model": provider.model}
    return result
