from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import BigInteger, Column, DateTime, Double, SmallInteger
from sqlmodel import Field, SQLModel


class AlertZone(SQLModel, table=True):
    __tablename__ = "alert_zones"
    __table_args__ = {"schema": "siaga"}

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    user_id: UUID = Field(foreign_key="siaga.users.id", unique=True, nullable=False)
    latitude: float = Field(sa_column=Column(Double, nullable=False))
    longitude: float = Field(sa_column=Column(Double, nullable=False))
    radius_km: int = Field(sa_column=Column(SmallInteger, nullable=False))
    notify_earthquake: bool
    notify_weather: bool
    zone_version: int = Field(sa_column=Column(BigInteger, nullable=False))
    alert_eligible_since: datetime = Field(
        sa_column=Column(DateTime(timezone=True), nullable=False)
    )
    created_at: datetime = Field(sa_column=Column(DateTime(timezone=True), nullable=False))
    updated_at: datetime = Field(sa_column=Column(DateTime(timezone=True), nullable=False))
