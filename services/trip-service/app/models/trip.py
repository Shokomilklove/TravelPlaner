from app.db_types import JSONType
from app.extensions import db
from app.utils import utcnow, uuid_str

TRIP_STATUSES = ("draft", "planning", "planned")


class Trip(db.Model):
    __tablename__ = "trips"

    id = db.Column(db.String(36), primary_key=True, default=uuid_str)
    user_id = db.Column(
        db.String(36),
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title = db.Column(db.String(255), nullable=False)
    origin = db.Column(db.String(255), nullable=False)
    destination = db.Column(db.String(255), nullable=False)
    start_date = db.Column(db.Date, nullable=False)
    end_date = db.Column(db.Date, nullable=False)
    budget_amount = db.Column(db.Numeric(12, 2), nullable=True)
    budget_currency = db.Column(db.String(3), nullable=False, default="USD")
    travelers = db.Column(db.Integer, nullable=False, default=1)
    preferences = db.Column(JSONType, nullable=True)
    status = db.Column(db.String(20), nullable=False, default="draft")
    is_saved = db.Column(db.Boolean, nullable=False, default=False)
    saved_at = db.Column(db.DateTime(timezone=True), nullable=True)
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = db.Column(
        db.DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False
    )

    user = db.relationship("User", back_populates="trips")
    itineraries = db.relationship(
        "Itinerary",
        back_populates="trip",
        cascade="all, delete-orphan",
        order_by="Itinerary.created_at.desc()",
        lazy="dynamic",
    )

    def latest_itinerary(self):
        return self.itineraries.first()

    def to_dict(self, include_itinerary=False):
        data = {
            "id": self.id,
            "user_id": self.user_id,
            "title": self.title,
            "origin": self.origin,
            "destination": self.destination,
            "start_date": self.start_date.isoformat() if self.start_date else None,
            "end_date": self.end_date.isoformat() if self.end_date else None,
            "budget_amount": float(self.budget_amount)
            if self.budget_amount is not None
            else None,
            "budget_currency": self.budget_currency,
            "travelers": self.travelers,
            "preferences": self.preferences or {},
            "status": self.status,
            "is_saved": self.is_saved,
            "saved_at": self.saved_at.isoformat() if self.saved_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
        if include_itinerary:
            itinerary = self.latest_itinerary()
            data["itinerary"] = itinerary.to_dict() if itinerary else None
        return data
