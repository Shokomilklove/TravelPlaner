"""initial schema: users, trips, itineraries

Revision ID: 0001
Revises:
Create Date: 2026-07-22

"""
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "users",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("full_name", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    op.create_table(
        "trips",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("origin", sa.String(length=255), nullable=False),
        sa.Column("destination", sa.String(length=255), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=False),
        sa.Column("budget_amount", sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column("budget_currency", sa.String(length=3), nullable=False, server_default="USD"),
        sa.Column("travelers", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("preferences", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="draft"),
        sa.Column("is_saved", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("saved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_trips_user_id", "trips", ["user_id"])

    op.create_table(
        "itineraries",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("trip_id", sa.String(length=36), nullable=False),
        sa.Column("provider", sa.String(length=50), nullable=True),
        sa.Column("model_used", sa.String(length=100), nullable=True),
        sa.Column("summary", sa.Text(), nullable=True),
        sa.Column("total_estimated_cost", sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column("currency", sa.String(length=3), nullable=False, server_default="USD"),
        sa.Column("plan", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["trip_id"], ["trips.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_itineraries_trip_id", "itineraries", ["trip_id"])


def downgrade():
    op.drop_index("ix_itineraries_trip_id", table_name="itineraries")
    op.drop_table("itineraries")
    op.drop_index("ix_trips_user_id", table_name="trips")
    op.drop_table("trips")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
