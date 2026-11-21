import re
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.common import Meta
from app.schemas.events import Category, Page

ReportStatus = Literal["pending", "in_review", "verified", "rejected"]


class ReportFields(BaseModel):
    id: UUID
    source: Literal["CITIZEN"] = "CITIZEN"
    event_id: UUID | None
    category: Category
    description: str
    latitude: float
    longitude: float
    has_photo: bool
    is_simulated: bool
    created_at: datetime
    match_distance_km: float | None


class ReportPublic(ReportFields):
    status: Literal["verified"]
    verified_at: datetime


class ReportPrivate(ReportFields):
    status: ReportStatus
    verified_at: datetime | None
    reporter_id: UUID
    reviewer_id: UUID | None
    version: int
    client_request_id: UUID
    payload_hash: str
    payload_hash_algo: Literal["report-payload-v1"]
    claimed_at: datetime | None
    decided_at: datetime | None
    latest_reason: str | None
    updated_at: datetime


class VerificationQuery(BaseModel):
    limit: int = Field(default=20, ge=1, le=50)
    offset: int = Field(default=0, ge=0)


class ReportListQuery(VerificationQuery):
    scope: Literal["nearby", "mine", "review", "verified"] = "nearby"
    category: Category | None = None
    status: ReportStatus | None = None
    event_id: UUID | None = None


class ReportListMeta(Meta):
    zone_version: int | None = None


class ReportFeed(BaseModel):
    items: list[ReportPrivate | ReportPublic]
    page: Page
    meta: ReportListMeta


class PhotoUrlData(BaseModel):
    url: str
    expires_at: datetime
    expires_in: Literal[300]
    content_type: Literal["image/jpeg"] = "image/jpeg"
    is_simulated: bool


class SignedPhotoQuery(BaseModel):
    expires: int
    signature: str = Field(pattern=r"^[A-Za-z0-9_-]{43}$")

    @field_validator("expires", mode="before")
    @classmethod
    def unix_seconds(cls, value):
        if not isinstance(value, str) or not re.fullmatch(r"-?[0-9]+", value):
            raise ValueError("Expected integer Unix seconds")
        return value


class ClaimRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    expected_version: int = Field(strict=True, ge=1)


class DecisionRequest(ClaimRequest):
    outcome: Literal["verified", "rejected"]
    reason: str


class ModerationResult(BaseModel):
    id: UUID
    status: ReportStatus
    reviewer_id: UUID | None
    version: int
    claimed_at: datetime | None
    decided_at: datetime | None


class VerificationDTO(BaseModel):
    id: UUID
    report_id: UUID
    moderator_id: UUID
    from_status: Literal["pending", "in_review"]
    to_status: Literal["in_review", "verified", "rejected"]
    reason: str
    resulting_version: int
    created_at: datetime


class VerificationFeed(BaseModel):
    items: list[VerificationDTO]
    page: Page
    meta: Meta
