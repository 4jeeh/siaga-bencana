from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import BigInteger, DateTime
from sqlalchemy.dialects.postgresql import JSONB
from sqlmodel import Field, SQLModel


class DisasterEvent(SQLModel, table=True):
    __tablename__ = "disaster_events"
    __table_args__ = {"schema": "siaga"}

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    source: str
    source_key: str
    category: str
    title: str
    occurred_at: datetime = Field(sa_type=DateTime(timezone=True))
    latitude: float | None = Field(default=None)
    longitude: float | None = Field(default=None)
    magnitude: float | None = Field(default=None)
    depth_km: float | None = Field(default=None)
    region: str | None = Field(default=None)
    latitude_text: str | None = Field(default=None)
    longitude_text: str | None = Field(default=None)
    potential: str | None = Field(default=None)
    felt: str | None = Field(default=None)
    shakemap_url: str | None = Field(default=None)
    source_url: str
    sender: str | None = Field(default=None)
    sent: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    status: str | None = Field(default=None)
    msg_type: str | None = Field(default=None)
    language: str | None = Field(default=None)
    cap_event: str | None = Field(default=None)
    event_code: str | None = Field(default=None)
    severity: str | None = Field(default=None)
    urgency: str | None = Field(default=None)
    certainty: str | None = Field(default=None)
    effective: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    expires: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    headline: str | None = Field(default=None)
    description: str | None = Field(default=None)
    web_url: str | None = Field(default=None)
    lifecycle_complete: bool = Field(default=True)
    cancelled_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    superseded_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    content_version: int = Field(default=1, sa_type=BigInteger)
    content_hash: str
    first_seen_at: datetime = Field(sa_type=DateTime(timezone=True))
    last_seen_at: datetime = Field(sa_type=DateTime(timezone=True))
    is_simulated: bool = Field(default=False)
    provenance: dict = Field(default_factory=dict, sa_type=JSONB(none_as_null=True))


class EventArea(SQLModel, table=True):
    __tablename__ = "event_areas"
    __table_args__ = {"schema": "siaga"}

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    event_id: UUID = Field(foreign_key="siaga.disaster_events.id")
    position: int
    area_description: str


class AreaPolygon(SQLModel, table=True):
    __tablename__ = "area_polygons"
    __table_args__ = {"schema": "siaga"}

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    area_id: UUID = Field(foreign_key="siaga.event_areas.id")
    position: int
    geometry_valid: bool
    invalid_reason: str | None = Field(default=None)
    centroid_latitude: float | None = Field(default=None)
    centroid_longitude: float | None = Field(default=None)
    south: float | None = Field(default=None)
    north: float | None = Field(default=None)
    west: float | None = Field(default=None)
    east: float | None = Field(default=None)
    crosses_antimeridian: bool | None = Field(default=None)


class PolygonVertex(SQLModel, table=True):
    __tablename__ = "polygon_vertices"
    __table_args__ = {"schema": "siaga"}

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    polygon_id: UUID = Field(foreign_key="siaga.area_polygons.id")
    sequence: int
    latitude: float
    longitude: float


class EventReference(SQLModel, table=True):
    __tablename__ = "event_references"
    __table_args__ = {"schema": "siaga"}

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    event_id: UUID = Field(foreign_key="siaga.disaster_events.id")
    referenced_source_key: str
    referenced_sender: str
    referenced_sent: datetime = Field(sa_type=DateTime(timezone=True))
    relation_type: str
    referenced_event_id: UUID | None = Field(default=None, foreign_key="siaga.disaster_events.id")
