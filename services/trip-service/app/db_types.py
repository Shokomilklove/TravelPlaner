"""Portable column types.

``JSONType`` stores structured data as native ``JSONB`` on PostgreSQL (fast,
indexable) while transparently falling back to generic ``JSON`` on SQLite so
the test-suite can run without a PostgreSQL server.
"""
from sqlalchemy import JSON
from sqlalchemy.dialects.postgresql import JSONB

JSONType = JSON().with_variant(JSONB, "postgresql")
