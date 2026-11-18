"""Read projection of siaga.citizen_reports for verified map markers."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime
from sqlmodel import Field, SQLModel


class CitizenReport(SQLModel, table=True):
    __tablename__ = "citizen_reports"
    __table_args__ = {"schema": "siaga"}

    id: UUID = Field(primary_key=True)
    category: str
    description: str
    latitude: float
    longitude: float
    status: str
    created_at: datetime = Field(sa_type=DateTime(timezone=True))
    is_simulated: bool
