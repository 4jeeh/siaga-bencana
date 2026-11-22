import re
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.errors import ApiError
from app.schemas.common import Meta
from app.schemas.events import EventCategory, Label, Page

MAX_SEQUENCE = 2**63 - 1
CANONICAL_SEQ_RE = re.compile(r"^(?:0|[1-9][0-9]*)$")
LOWER_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


def invalid_query(field: str) -> ApiError:
    path = "header.Last-Event-ID" if field == "Last-Event-ID" else f"query.{field}"
    return ApiError(
        422, "VALIDATION_ERROR", "Parameter notifikasi tidak valid.",
        {"fields": [{"field": path, "code": "invalid_value"}]},
    )


def parse_sequence(raw: str, *, field: str) -> int:
    if len(raw) > 19 or not CANONICAL_SEQ_RE.fullmatch(raw):
        raise invalid_query(field)
    value = int(raw)
    if value > MAX_SEQUENCE:
        raise invalid_query(field)
    return value


def parse_cursor_user_id(raw: str, *, field: str) -> UUID:
    if not LOWER_UUID_RE.fullmatch(raw):
        raise invalid_query(field)
    return UUID(raw)


class NotificationHistoryQuery(BaseModel):
    limit: int = Field(default=20, ge=1, le=50)
    offset: int = Field(default=0, ge=0)
    unread_only: bool = False

    @field_validator("unread_only", mode="before")
    @classmethod
    def canonical_bool(cls, value):
        if isinstance(value, bool) or value in ("true", "false"):
            return value
        raise ValueError("Gunakan true atau false.")

    @field_validator("limit", "offset", mode="before")
    @classmethod
    def canonical_int(cls, value):
        if isinstance(value, str) and not CANONICAL_SEQ_RE.fullmatch(value):
            raise ValueError("Gunakan bilangan bulat nonnegatif.")
        return value


class NotificationSyncQuery(BaseModel):
    baseline: str | None = None
    since_sequence: str | None = None
    cursor_user_id: str | None = None
    limit: str | None = None

    def catch_up(self) -> tuple[UUID, int, int] | None:
        if self.baseline == "true":
            for field in ("since_sequence", "cursor_user_id", "limit"):
                if getattr(self, field) is not None:
                    raise invalid_query(field)
            return None
        if self.baseline not in (None, "false"):
            raise invalid_query("baseline")
        if self.since_sequence is None:
            raise invalid_query("since_sequence")
        if self.cursor_user_id is None:
            raise invalid_query("cursor_user_id")
        owner = parse_cursor_user_id(self.cursor_user_id, field="cursor_user_id")
        since = parse_sequence(self.since_sequence, field="since_sequence")
        limit = 20 if self.limit is None else parse_sequence(self.limit, field="limit")
        if not 1 <= limit <= 50:
            raise invalid_query("limit")
        return owner, since, limit


class NotificationStreamQuery(BaseModel):
    since_sequence: str | None = None
    cursor_user_id: str | None = None

    def cursor(self, last_event_ids: list[str] | None) -> tuple[UUID, int]:
        if last_event_ids:
            if len(last_event_ids) != 1:
                raise invalid_query("Last-Event-ID")
            owner, _, sequence = last_event_ids[0].partition(":")
            return (
                parse_cursor_user_id(owner, field="Last-Event-ID"),
                parse_sequence(sequence, field="Last-Event-ID"),
            )
        if self.cursor_user_id is None:
            raise invalid_query("cursor_user_id")
        if self.since_sequence is None:
            raise invalid_query("since_sequence")
        return (
            parse_cursor_user_id(self.cursor_user_id, field="cursor_user_id"),
            parse_sequence(self.since_sequence, field="since_sequence"),
        )


class NotificationReadRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")


class NotificationReadData(BaseModel):
    id: UUID
    read_at: datetime


class NotificationDTO(BaseModel):
    id: UUID
    event_id: UUID
    kind: Literal["official_new"]
    sequence: int
    zone_version: int
    priority_algo: Literal["eq-priority-v1", "cap-priority-v1"]
    priority_score: float | None
    priority_label: Label
    priority_reasons: list[dict]
    priority_components: dict[str, float] | None
    match_method: Literal["point_distance", "inside_polygon", "near_polygon_sample"]
    match_distance_km: float
    evaluated_at: datetime
    created_at: datetime
    read_at: datetime | None
    is_simulated: bool
    title: str
    event_category: EventCategory
    current_lifecycle_status: str
    present_as_active_alert: bool


class NotificationHistoryFeed(BaseModel):
    items: list[NotificationDTO]
    page: Page
    unread_count: int
    meta: Meta


class NotificationSyncFeed(BaseModel):
    items: list[NotificationDTO]
    cursor_user_id: UUID
    high_water_mark: int
    next_sequence: int
    has_more: bool
    meta: Meta
