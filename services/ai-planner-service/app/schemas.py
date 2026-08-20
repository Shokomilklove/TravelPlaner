"""Pydantic schemas for request validation and LLM-output validation."""
import re
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, field_validator


def coerce_cost(value):
    """Best-effort conversion of an LLM-provided cost into a float."""
    if value is None or isinstance(value, bool):
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        cleaned = re.sub(r"[^0-9.]", "", value.replace(",", ""))
        try:
            return float(cleaned) if cleaned else 0.0
        except ValueError:
            return 0.0
    return 0.0


# --------------------------------------------------------------------------
# Inbound request schemas
# --------------------------------------------------------------------------
class PlanRequest(BaseModel):
    origin: str = Field(min_length=1)
    destination: str = Field(min_length=1)
    start_date: str
    end_date: str
    budget: Optional[float] = None
    currency: str = "USD"
    travelers: int = Field(default=1, ge=1)
    preferences: Dict[str, Any] = Field(default_factory=dict)


class OptimizeRequest(PlanRequest):
    current_plan: Dict[str, Any] = Field(default_factory=dict)
    goal: str = "reduce total cost while keeping the trip enjoyable"


# --------------------------------------------------------------------------
# LLM output schema (what the model is asked to return)
# --------------------------------------------------------------------------
class ItineraryItem(BaseModel):
    type: str = "activity"
    title: str
    description: Optional[str] = ""
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    estimated_cost: float = 0.0
    currency: str = "USD"
    metadata: Dict[str, Any] = Field(default_factory=dict)

    @field_validator("estimated_cost", mode="before")
    @classmethod
    def _coerce_estimated_cost(cls, v):
        return coerce_cost(v)


class DayPlan(BaseModel):
    day: int
    date: Optional[str] = None
    title: Optional[str] = None
    items: List[ItineraryItem] = Field(default_factory=list)


class LLMPlan(BaseModel):
    summary: str
    days: List[DayPlan] = Field(default_factory=list)
    flights: List[ItineraryItem] = Field(default_factory=list)
    accommodation: List[ItineraryItem] = Field(default_factory=list)
    activities: List[ItineraryItem] = Field(default_factory=list)
    total_estimated_cost: Optional[float] = None
    currency: Optional[str] = None

    @field_validator("total_estimated_cost", mode="before")
    @classmethod
    def _coerce_total(cls, v):
        if v is None:
            return None
        return coerce_cost(v)
