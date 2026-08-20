import time

from flask import Blueprint, current_app, jsonify, request
from pydantic import ValidationError

from app.auth import require_internal_token
from app.metrics import AI_GENERATION_DURATION, AI_GENERATION_REQUESTS
from app.planner import PlanningError, generate_plan
from app.schemas import OptimizeRequest, PlanRequest

bp = Blueprint("plan", __name__, url_prefix="/api")


def _provider_or_503():
    provider = current_app.llm_provider
    if provider is None:
        return None, (
            jsonify(
                {
                    "error": "provider_unavailable",
                    "message": "No AI provider is configured. Set AI_PROVIDER and "
                    "the corresponding credentials.",
                }
            ),
            503,
        )
    return provider, None


def _run(provider, req_dict, extra_instructions=None):
    start = time.perf_counter()
    try:
        result = generate_plan(
            provider,
            req_dict,
            max_retries=current_app.config["AI_MAX_RETRIES"],
            extra_instructions=extra_instructions,
        )
    except PlanningError as exc:
        AI_GENERATION_REQUESTS.labels(provider.name, "error").inc()
        AI_GENERATION_DURATION.labels(provider.name).observe(time.perf_counter() - start)
        current_app.logger.warning(
            "plan generation failed",
            extra={"provider": provider.name, "error": exc.message},
        )
        return jsonify({"error": "generation_failed", "message": exc.message}), exc.status_code

    AI_GENERATION_REQUESTS.labels(provider.name, "success").inc()
    AI_GENERATION_DURATION.labels(provider.name).observe(time.perf_counter() - start)
    return jsonify(result), 200


@bp.post("/plan")
@require_internal_token
def plan():
    try:
        req = PlanRequest.model_validate(request.get_json(force=True, silent=True) or {})
    except ValidationError as exc:
        return (
            jsonify(
                {
                    "error": "validation_error",
                    "message": "Invalid plan request",
                    "details": exc.errors(),
                }
            ),
            400,
        )

    provider, err = _provider_or_503()
    if err:
        return err
    return _run(provider, req.model_dump())


@bp.post("/optimize")
@require_internal_token
def optimize():
    try:
        req = OptimizeRequest.model_validate(
            request.get_json(force=True, silent=True) or {}
        )
    except ValidationError as exc:
        return (
            jsonify(
                {
                    "error": "validation_error",
                    "message": "Invalid optimize request",
                    "details": exc.errors(),
                }
            ),
            400,
        )

    provider, err = _provider_or_503()
    if err:
        return err

    import json

    extra = (
        f"Optimization goal: {req.goal}.\n"
        "Improve upon this existing plan where possible:\n"
        f"{json.dumps(req.current_plan)[:4000]}"
    )
    payload = req.model_dump()
    payload.pop("current_plan", None)
    payload.pop("goal", None)
    return _run(provider, payload, extra_instructions=extra)
