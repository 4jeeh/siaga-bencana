from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime
from sqlalchemy.dialects.postgresql import JSONB
from sqlmodel import Field, SQLModel


class SyncRun(SQLModel, table=True):
    __tablename__ = "sync_runs"
    __table_args__ = {"schema": "siaga"}

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    source: str
    status: str
    lease_token: UUID = Field(default_factory=uuid4)
    lease_until: datetime = Field(sa_type=DateTime(timezone=True))
    started_at: datetime = Field(sa_type=DateTime(timezone=True))
    finished_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    last_success_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    bootstrap_completed: bool = Field(default=False)
    checkpoint: dict = Field(default_factory=dict, sa_type=JSONB(none_as_null=True))
    valid_count: int = Field(default=0)
    invalid_count: int = Field(default=0)
    changed_count: int = Field(default=0)
    error_code: str | None = Field(default=None)
    error_summary: str | None = Field(default=None)
