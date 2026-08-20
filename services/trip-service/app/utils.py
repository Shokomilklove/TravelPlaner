"""Small shared helpers."""
import uuid
from datetime import datetime, timezone


def uuid_str():
    return str(uuid.uuid4())


def utcnow():
    return datetime.now(timezone.utc)
