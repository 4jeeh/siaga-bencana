from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import BigInteger, DateTime
from sqlalchemy.dialects.postgresql import JSONB
from sqlmodel import Field, SQLModel


class NotificationLog(SQLModel, table=True):
    __tablename__ = "notification_logs"
    __table_args__ = {"schema": "siaga"}

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    user_id: UUID = Field(foreign_key="siaga.users.id")
    event_id: UUID = Field(foreign_key="siaga.disaster_events.id")
    kind: str = Field(default="official_new")
    sequence: int = Field(sa_type=BigInteger)
    zone_version: int = Field(sa_type=BigInteger)
    priority_algo: str
    priority_score: float | None = Field(default=None)
    priority_label: str
    priority_reasons: list[dict] = Field(sa_type=JSONB(none_as_null=True))
    priority_components: dict | None = Field(default=None, sa_type=JSONB(none_as_null=True))
    match_method: str
    match_distance_km: float
    evaluated_at: datetime = Field(sa_type=DateTime(timezone=True))
    created_at: datetime = Field(sa_type=DateTime(timezone=True))
    read_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    is_simulated: bool = Field(default=False)
