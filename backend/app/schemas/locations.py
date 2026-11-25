from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class LocationSearchQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")
    q: str
    limit: int = Field(default=6, ge=1, le=10)

    @field_validator("q")
    @classmethod
    def validate_query(cls, value: str) -> str:
        value = value.strip()
        if not 2 <= len(value) <= 100:
            raise ValueError("Masukkan 2 sampai 100 karakter.")
        return value


class LocationSuggestion(BaseModel):
    label: str
    subtitle: str | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    source: Literal["NOMINATIM", "LOCAL_FALLBACK"]


class LocationSearchData(BaseModel):
    items: list[LocationSuggestion]
