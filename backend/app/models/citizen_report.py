from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import BigInteger, DateTime, Double, Text, UniqueConstraint
from sqlmodel import Field, SQLModel

TIMESTAMPTZ = DateTime(timezone=True)


def utc_now() -> datetime:
    return datetime.now(UTC)


class CitizenReport(SQLModel, table=True):
    __tablename__ = "citizen_reports"
    __table_args__ = (UniqueConstraint("reporter_id", "client_request_id"), {"schema": "siaga"})

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    reporter_id: UUID = Field(foreign_key="siaga.users.id", ondelete="RESTRICT")
    event_id: UUID | None = Field(
        default=None, foreign_key="siaga.disaster_events.id", ondelete="RESTRICT"
    )
    client_request_id: UUID
    payload_hash: str = Field(sa_type=Text)
    payload_hash_algo: str = Field(default="report-payload-v1", sa_type=Text)
    category: str = Field(sa_type=Text)
    description: str = Field(sa_type=Text)
    latitude: float = Field(sa_type=Double)
    longitude: float = Field(sa_type=Double)
    status: str = Field(default="pending", sa_type=Text)
    reviewer_id: UUID | None = Field(
        default=None, foreign_key="siaga.users.id", ondelete="RESTRICT"
    )
    version: int = Field(default=1, sa_type=BigInteger)
    claimed_at: datetime | None = Field(default=None, sa_type=TIMESTAMPTZ)
    decided_at: datetime | None = Field(default=None, sa_type=TIMESTAMPTZ)
    photo_storage_backend: str | None = Field(default=None, sa_type=Text)
    photo_object_key: str | None = Field(default=None, unique=True, sa_type=Text)
    photo_sha256: str | None = Field(default=None, sa_type=Text)
    photo_bytes: int | None = None
    photo_width: int | None = None
    photo_height: int | None = None
    is_simulated: bool = False
    created_at: datetime = Field(default_factory=utc_now, sa_type=TIMESTAMPTZ)
    updated_at: datetime = Field(default_factory=utc_now, sa_type=TIMESTAMPTZ)


class ReportVerification(SQLModel, table=True):
    __tablename__ = "report_verifications"
    __table_args__ = (UniqueConstraint("report_id", "resulting_version"), {"schema": "siaga"})

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    report_id: UUID = Field(foreign_key="siaga.citizen_reports.id", ondelete="RESTRICT")
    moderator_id: UUID = Field(foreign_key="siaga.users.id", ondelete="RESTRICT")
    from_status: str = Field(sa_type=Text)
    to_status: str = Field(sa_type=Text)
    reason: str = Field(sa_type=Text)
    resulting_version: int = Field(sa_type=BigInteger)
    created_at: datetime = Field(default_factory=utc_now, sa_type=TIMESTAMPTZ)


class MediaCleanupJob(SQLModel, table=True):
    __tablename__ = "media_cleanup_jobs"
    __table_args__ = {"schema": "siaga"}

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    storage_backend: str = Field(sa_type=Text)
    object_key: str = Field(unique=True, sa_type=Text)
    status: str = Field(default="pending", sa_type=Text)
    attempts: int = 0
    next_attempt_at: datetime = Field(default_factory=utc_now, sa_type=TIMESTAMPTZ)
    lease_token: UUID | None = None
    lease_until: datetime | None = Field(default=None, sa_type=TIMESTAMPTZ)
    object_created_at: datetime = Field(sa_type=TIMESTAMPTZ)
    last_error: str | None = Field(default=None, sa_type=Text)
    created_at: datetime = Field(default_factory=utc_now, sa_type=TIMESTAMPTZ)
    updated_at: datetime = Field(default_factory=utc_now, sa_type=TIMESTAMPTZ)
