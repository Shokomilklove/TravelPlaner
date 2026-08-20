from app.db_types import JSONType
from app.extensions import db
from app.utils import utcnow, uuid_str


class Itinerary(db.Model):
    __tablename__ = "itineraries"

    id = db.Column(db.String(36), primary_key=True, default=uuid_str)
    trip_id = db.Column(
        db.String(36),
        db.ForeignKey("trips.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    provider = db.Column(db.String(50), nullable=True)
    model_used = db.Column(db.String(100), nullable=True)
    summary = db.Column(db.Text, nullable=True)
    total_estimated_cost = db.Column(db.Numeric(12, 2), nullable=True)
    currency = db.Column(db.String(3), nullable=False, default="USD")
    # Full structured plan returned by the AI Planner service.
    plan = db.Column(JSONType, nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow, nullable=False)

    trip = db.relationship("Trip", back_populates="itineraries")

    def to_dict(self):
        return {
            "id": self.id,
            "trip_id": self.trip_id,
            "provider": self.provider,
            "model_used": self.model_used,
            "summary": self.summary,
            "total_estimated_cost": float(self.total_estimated_cost)
            if self.total_estimated_cost is not None
            else None,
            "currency": self.currency,
            "plan": self.plan,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
