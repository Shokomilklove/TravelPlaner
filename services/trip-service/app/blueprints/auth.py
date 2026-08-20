from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import create_access_token, get_jwt_identity, jwt_required

from app.extensions import db
from app.metrics import USERS_REGISTERED
from app.models import User
from app.schemas.auth import LoginSchema, RegisterSchema

bp = Blueprint("auth", __name__, url_prefix="/api/auth")


@bp.post("/register")
def register():
    data = RegisterSchema().load(request.get_json(force=True, silent=True) or {})
    email = data["email"].lower().strip()

    if User.query.filter_by(email=email).first():
        return jsonify({"error": "conflict", "message": "Email already registered"}), 409

    user = User(email=email, full_name=data["full_name"].strip())
    user.set_password(data["password"])
    db.session.add(user)
    db.session.commit()
    USERS_REGISTERED.inc()

    current_app.logger.info("user registered", extra={"user_id": user.id})
    token = create_access_token(identity=user.id)
    return jsonify({"access_token": token, "user": user.to_dict()}), 201


@bp.post("/login")
def login():
    data = LoginSchema().load(request.get_json(force=True, silent=True) or {})
    email = data["email"].lower().strip()

    user = User.query.filter_by(email=email).first()
    if user is None or not user.check_password(data["password"]):
        return jsonify({"error": "unauthorized", "message": "Invalid email or password"}), 401

    token = create_access_token(identity=user.id)
    return jsonify({"access_token": token, "user": user.to_dict()}), 200


@bp.get("/me")
@jwt_required()
def me():
    user = db.session.get(User, get_jwt_identity())
    if user is None:
        return jsonify({"error": "not_found", "message": "User not found"}), 404
    return jsonify({"user": user.to_dict()}), 200
