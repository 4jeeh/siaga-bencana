from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, JsonValue

from app.schemas.common import Meta

EventCategory = Literal["earthquake", "extreme_weather"]
Category = Literal["earthquake", "flood", "eruption", "extreme_weather", "haze_other"]
OfficialSource = Literal["BMKG_TEWS", "BMKG_NOWCAST"]
Label = Literal["ordinary", "attention", "high", "information", "unavailable"]
Match = Literal["point_distance", "inside_polygon", "near_polygon_sample", "no_geometry"]


class FeedQuery(BaseModel):
    category: EventCategory | None = None
    radius_only: bool = True
    weather_status: Literal["active", "all"] = "active"
    sort: Literal["recent", "priority"] = "recent"
    limit: int = Field(default=20, ge=1, le=50)
    offset: int = Field(default=0, ge=0)


class MapQuery(BaseModel):
    category: Category | None = None
    radius_only: bool = True
    include_reports: bool = True
    bbox: str | None = None


class Freshness(BaseModel):
    source: OfficialSource
    state: Literal["healthy", "degraded", "stale", "unavailable"]
    last_success_at: datetime | None
    last_attempt_at: datetime | None


class EventMeta(Meta):
    zone_version: int
    sources: list[Freshness]


class Reason(BaseModel):
    code: str
    text: str
    values: dict[str, JsonValue]


class Priority(BaseModel):
    priority_algo: Literal["eq-priority-v1", "cap-priority-v1"]
    priority_score: float | None
    priority_display: str | None
    priority_label: Label
    priority_reasons: list[Reason]
    components: dict[str, float] | None
    match_method: Match
    match_distance_km: float | None
    within_radius: bool | None
    evaluated_at: datetime
    zone_version: int


class CapSummary(BaseModel):
    severity: str | None
    urgency: str | None
    certainty: str | None
    effective: datetime
    expires: datetime | None
    area_descriptions: list[str]


class EventSummary(BaseModel):
    id: UUID
    source: OfficialSource
    category: EventCategory
    title: str
    occurred_at: datetime
    latitude: float | None
    longitude: float | None
    is_simulated: bool
    content_version: int
    lifecycle_status: Literal[
        "current",
        "historical",
        "invalid_time",
        "active",
        "scheduled",
        "expired",
        "cancelled",
        "superseded",
        "incomplete",
    ]
    priority: Priority
    cap: CapSummary | None


class Earthquake(BaseModel):
    magnitude: float | None
    depth_km: float | None
    region: str | None
    latitude_text: str | None
    longitude_text: str | None
    potential: str | None
    felt: str | None
    shakemap_url: str | None


class Weather(BaseModel):
    sender: str
    sent: datetime
    status: str
    msg_type: str
    language: str | None
    cap_event: str | None
    event_code: str | None
    headline: str | None
    description: str | None
    web_url: str | None
    lifecycle_complete: bool


class Vertex(BaseModel):
    sequence: int
    latitude: float
    longitude: float


class Polygon(BaseModel):
    id: UUID
    position: int
    geometry_valid: bool
    centroid_latitude: float | None
    centroid_longitude: float | None
    south: float | None
    north: float | None
    west: float | None
    east: float | None
    crosses_antimeridian: bool | None
    vertices: list[Vertex]


class Area(BaseModel):
    id: UUID
    position: int
    area_description: str
    polygons: list[Polygon]


class Reference(BaseModel):
    relation_type: str
    referenced_source_key: str
    referenced_event_id: UUID | None


class EventDetail(EventSummary):
    source_url: str
    first_seen_at: datetime
    last_seen_at: datetime
    earthquake: Earthquake | None
    weather: Weather | None
    areas: list[Area]
    references: list[Reference]


class Page(BaseModel):
    limit: int
    offset: int
    next_offset: int | None
    has_more: bool


class Feed(BaseModel):
    items: list[EventSummary]
    page: Page
    meta: EventMeta


class Detail(BaseModel):
    data: EventDetail
    meta: EventMeta


class Marker(BaseModel):
    magnitude: float | None = None
    depth_km: float | None = None
    potential: str | None = None
    id: UUID
    kind: Literal["event", "report"]
    source: Literal["BMKG_TEWS", "BMKG_NOWCAST", "CITIZEN"]
    category: Category
    title: str
    latitude: float
    longitude: float
    match_method: Literal["point_distance", "inside_polygon", "near_polygon_sample"]
    match_distance_km: float
    priority_label: Label | None
    is_simulated: bool


class MarkerFeed(BaseModel):
    items: list[Marker]
    truncated: bool
    cap: Literal[100]
    meta: EventMeta
