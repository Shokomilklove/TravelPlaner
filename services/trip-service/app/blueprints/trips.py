import time

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import get_jwt_identity, jwt_required

from app.clients.ai_planner import AIPlannerError
from app.extensions import db
from app.metrics import (
    AI_PLAN_DURATION,
    AI_PLAN_FAILURES,
    AI_PLAN_REQUESTS,
    TRIPS_CREATED,
    TRIPS_SAVED,
)
from app.models import Itinerary, Trip
from app.schemas.trip import TripCreateSchema, TripUpdateSchema
from app.utils import utcnow

bp = Blueprint("trips", __name__, url_prefix="/api/trips")


def _get_owned_trip(trip_id):
    """Return the trip if it exists and belongs to the caller, else None."""
    trip = db.session.get(Trip, trip_id)
    if trip is None or trip.user_id != get_jwt_identity():
        return None
    return trip


def _not_found():
    return jsonify({"error": "not_found", "message": "Trip not found"}), 404


def _as_float(value):
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


@bp.get("")
@jwt_required()
def list_trips():
    query = Trip.query.filter_by(user_id=get_jwt_identity())

    status = request.args.get("status")
    if status:
        query = query.filter_by(status=status)

    saved = request.args.get("saved")
    if saved is not None:
        query = query.filter_by(is_saved=saved.lower() in ("1", "true", "yes"))

    trips = query.order_by(Trip.created_at.desc()).all()
    return jsonify({"trips": [t.to_dict() for t in trips]}), 200


@bp.post("")
@jwt_required()
def create_trip():
    data = TripCreateSchema().load(request.get_json(force=True, silent=True) or {})
    trip = Trip(
        user_id=get_jwt_identity(),
        title=data.get("title") or f"{data['origin']} to {data['destination']}",
        origin=data["origin"],
        destination=data["destination"],
        start_date=data["start_date"],
        end_date=data["end_date"],
        budget_amount=data.get("budget_amount"),
        budget_currency=(data.get("budget_currency") or "USD").upper(),
        travelers=data.get("travelers", 1),
        preferences=data.get("preferences") or {},
        status="draft",
    )
    db.session.add(trip)
    db.session.commit()
    TRIPS_CREATED.inc()
    return jsonify({"trip": trip.to_dict()}), 201


@bp.get("/<trip_id>")
@jwt_required()
def get_trip(trip_id):
    trip = _get_owned_trip(trip_id)
    if trip is None:
        return _not_found()
    return jsonify({"trip": trip.to_dict(include_itinerary=True)}), 200


@bp.put("/<trip_id>")
@jwt_required()
def update_trip(trip_id):
    trip = _get_owned_trip(trip_id)
    if trip is None:
        return _not_found()

    data = TripUpdateSchema().load(request.get_json(force=True, silent=True) or {})
    for field in (
        "title",
        "origin",
        "destination",
        "start_date",
        "end_date",
        "travelers",
        "preferences",
        "status",
        "budget_amount",
    ):
        if field in data:
            setattr(trip, field, data[field])
    if "budget_currency" in data:
        trip.budget_currency = data["budget_currency"].upper()

    if trip.end_date < trip.start_date:
        return (
            jsonify(
                {
                    "error": "validation_error",
                    "message": "end_date must be on or after start_date",
                }
            ),
            400,
        )

    db.session.commit()
    return jsonify({"trip": trip.to_dict(include_itinerary=True)}), 200


@bp.delete("/<trip_id>")
@jwt_required()
def delete_trip(trip_id):
    trip = _get_owned_trip(trip_id)
    if trip is None:
        return _not_found()
    db.session.delete(trip)
    db.session.commit()
    return "", 204


@bp.post("/<trip_id>/plan")
@jwt_required()
def plan_trip(trip_id):
    trip = _get_owned_trip(trip_id)
    if trip is None:
        return _not_found()

    payload = {
        "origin": trip.origin,
        "destination": trip.destination,
        "start_date": trip.start_date.isoformat(),
        "end_date": trip.end_date.isoformat(),
        "budget": _as_float(trip.budget_amount),
        "currency": trip.budget_currency,
        "travelers": trip.travelers,
        "preferences": trip.preferences or {},
    }

    client = current_app.ai_planner_client
    start = time.perf_counter()
    try:
        plan = client.plan(payload)
    except AIPlannerError as exc:
        AI_PLAN_REQUESTS.labels("error").inc()
        AI_PLAN_FAILURES.labels(str(exc.status_code)).inc()
        current_app.logger.warning(
            "AI planning failed",
            extra={"trip_id": trip.id, "error": exc.message},
        )
        return jsonify({"error": "ai_planner_error", "message": exc.message}), exc.status_code
    finally:
        AI_PLAN_DURATION.observe(time.perf_counter() - start)

    AI_PLAN_REQUESTS.labels("success").inc()

    meta = plan.get("meta", {}) if isinstance(plan, dict) else {}
    itinerary = Itinerary(
        trip_id=trip.id,
        provider=meta.get("provider"),
        model_used=meta.get("model"),
        summary=plan.get("summary"),
        total_estimated_cost=_as_float(plan.get("total_estimated_cost")),
        currency=plan.get("currency") or trip.budget_currency,
        plan=plan,
    )
    trip.status = "planned"
    db.session.add(itinerary)
    db.session.commit()

    current_app.logger.info(
        "itinerary generated",
        extra={"trip_id": trip.id, "provider": itinerary.provider},
    )
    return jsonify({"itinerary": itinerary.to_dict()}), 201


@bp.post("/<trip_id>/save")
@jwt_required()
def save_trip(trip_id):
    trip = _get_owned_trip(trip_id)
    if trip is None:
        return _not_found()
    if not trip.is_saved:
        trip.is_saved = True
        trip.saved_at = utcnow()
        db.session.commit()
        TRIPS_SAVED.inc()
    return jsonify({"trip": trip.to_dict()}), 200


@bp.post("/<trip_id>/unsave")
@jwt_required()
def unsave_trip(trip_id):
    trip = _get_owned_trip(trip_id)
    if trip is None:
        return _not_found()
    trip.is_saved = False
    trip.saved_at = None
    db.session.commit()
    return jsonify({"trip": trip.to_dict()}), 200


@bp.get("/<trip_id>/itinerary")
@jwt_required()
def get_itinerary(trip_id):
    trip = _get_owned_trip(trip_id)
    if trip is None:
        return _not_found()
    itinerary = trip.latest_itinerary()
    if itinerary is None:
        return jsonify({"error": "not_found", "message": "No itinerary yet"}), 404
    return jsonify({"itinerary": itinerary.to_dict()}), 200


@bp.get("/<trip_id>/itineraries")
@jwt_required()
def list_itineraries(trip_id):
    trip = _get_owned_trip(trip_id)
    if trip is None:
        return _not_found()
    items = trip.itineraries.all()
    return jsonify({"itineraries": [i.to_dict() for i in items]}), 200
