from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity, jwt_required

from app.extensions import db
from app.models import User
from app.schemas.user import UserUpdateSchema

bp = Blueprint("users", __name__, url_prefix="/api/users")


def _forbidden():
    return jsonify({"error": "forbidden", "message": "Access denied"}), 403


@bp.get("/<user_id>")
@jwt_required()
def get_user(user_id):
    if user_id != get_jwt_identity():
        return _forbidden()
    user = db.session.get(User, user_id)
    if user is None:
        return jsonify({"error": "not_found", "message": "User not found"}), 404
    return jsonify({"user": user.to_dict()}), 200


@bp.put("/<user_id>")
@jwt_required()
def update_user(user_id):
    if user_id != get_jwt_identity():
        return _forbidden()
    user = db.session.get(User, user_id)
    if user is None:
        return jsonify({"error": "not_found", "message": "User not found"}), 404

    data = UserUpdateSchema().load(request.get_json(force=True, silent=True) or {})
    if "full_name" in data:
        user.full_name = data["full_name"].strip()
    if "password" in data:
        user.set_password(data["password"])
    db.session.commit()
    return jsonify({"user": user.to_dict()}), 200
