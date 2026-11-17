from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ZoneRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    latitude: float = Field(ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)
    radius_km: Literal[25, 50, 100]
    notify_earthquake: bool
    notify_weather: bool

    @field_validator("latitude", "longitude", mode="before")
    @classmethod
    def require_number(cls, value):
        # JSON integers are coordinates too; bool is an int subclass in Python.
        if type(value) not in (int, float):
            raise ValueError("Coordinate must be a number")
        return value

    @field_validator("latitude", "longitude")
    @classmethod
    def canonicalize_zero(cls, value):
        return 0.0 if value == 0 else value

    @field_validator("longitude")
    @classmethod
    def canonicalize_antimeridian(cls, value):
        return -180.0 if value == 180 else value

    @field_validator("radius_km", mode="before")
    @classmethod
    def require_integer_radius(cls, value):
        # Literal alone accepts equal float values (e.g. 25.0).
        if type(value) is not int:
            raise ValueError("Radius must be an integer")
        return value


class ZoneDTO(BaseModel):
    id: UUID
    latitude: float
    longitude: float
    radius_km: Literal[25, 50, 100]
    notify_earthquake: bool
    notify_weather: bool
    zone_version: int = Field(gt=0)
    alert_eligible_since: datetime
    updated_at: datetime
