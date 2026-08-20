"""Builds the system and user prompts sent to the LLM."""
import json

SYSTEM_PROMPT = (
    "You are an expert travel planner. Given trip parameters you produce a "
    "concrete, realistic vacation plan including flights, accommodation and "
    "day-by-day activities. You always respond with STRICT, valid JSON only — "
    "no markdown, no code fences, no commentary. All monetary values are plain "
    "numbers expressed in the trip's currency."
)

# Compact schema description embedded in the user prompt so the model knows the
# exact shape to return.
_SCHEMA_EXAMPLE = {
    "summary": "1-3 sentence overview of the trip",
    "days": [
        {
            "day": 1,
            "date": "YYYY-MM-DD",
            "title": "short label for the day",
            "items": [
                {
                    "type": "activity|meal|transport",
                    "title": "string",
                    "description": "string",
                    "start_time": "HH:MM",
                    "end_time": "HH:MM",
                    "estimated_cost": 0,
                    "currency": "USD",
                }
            ],
        }
    ],
    "flights": [
        {
            "type": "flight",
            "title": "e.g. TLV to FCO (outbound)",
            "description": "string",
            "estimated_cost": 0,
            "currency": "USD",
            "metadata": {"from": "", "to": "", "airline": ""},
        }
    ],
    "accommodation": [
        {
            "type": "accommodation",
            "title": "hotel / rental name",
            "description": "string",
            "estimated_cost": 0,
            "currency": "USD",
            "metadata": {"nights": 0, "area": ""},
        }
    ],
    "activities": [
        {
            "type": "activity",
            "title": "string",
            "description": "string",
            "estimated_cost": 0,
            "currency": "USD",
        }
    ],
    "total_estimated_cost": 0,
    "currency": "USD",
}


def build_prompt(req, extra_instructions=None):
    """Return (system_prompt, user_prompt) for the given plan request dict."""
    budget_line = (
        f"Target budget: {req.get('budget')} {req.get('currency', 'USD')}."
        if req.get("budget") is not None
        else "No fixed budget; aim for good value."
    )
    prefs = req.get("preferences") or {}
    prefs_line = (
        f"Traveler preferences: {json.dumps(prefs)}." if prefs else "No specific preferences provided."
    )

    lines = [
        "Plan a vacation trip with the following parameters:",
        f"- Origin: {req.get('origin')}",
        f"- Destination: {req.get('destination')}",
        f"- Dates: {req.get('start_date')} to {req.get('end_date')}",
        f"- Travelers: {req.get('travelers', 1)}",
        f"- {budget_line}",
        f"- {prefs_line}",
        "",
        "Produce realistic flight options, accommodation, and a day-by-day "
        "itinerary of activities and meals. Keep costs realistic for the "
        "destination and dates. Ensure total_estimated_cost is the sum of all "
        "flights, accommodation and activity costs.",
    ]
    if extra_instructions:
        lines += ["", extra_instructions]

    lines += [
        "",
        "Return ONLY a JSON object with exactly this structure (values are examples):",
        json.dumps(_SCHEMA_EXAMPLE, indent=2),
    ]
    return SYSTEM_PROMPT, "\n".join(lines)
