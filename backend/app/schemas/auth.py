import re
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    email: str
    password: str = Field(min_length=10, max_length=128)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value):
        value = value.strip().lower()
        if len(value) > 254 or not re.fullmatch(
            r"[a-z0-9!#$%&'*+/=?^_`{|}~.-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,63}", value
        ):
            raise ValueError("Invalid email")
        local, domain = value.rsplit("@", 1)
        if (
            len(local) > 64
            or local.startswith(".")
            or local.endswith(".")
            or ".." in value
            or any(p.startswith("-") or p.endswith("-") or len(p) > 63 for p in domain.split("."))
        ):
            raise ValueError("Invalid email")
        return value


class RegisterRequest(LoginRequest):
    display_name: str

    @field_validator("display_name")
    @classmethod
    def normalize_name(cls, value):
        value = value.strip()
        if not 1 <= len(value) <= 80:
            raise ValueError("Invalid display name")
        return value


class UserDTO(BaseModel):
    id: UUID
    email: str
    display_name: str
    role: Literal["citizen", "admin"]
    has_zone: bool


class AuthData(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: Literal[3600] = 3600
    expires_at: datetime
    user: UserDTO
