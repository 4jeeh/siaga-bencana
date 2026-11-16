from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import BigInteger, Column, DateTime, Text
from sqlmodel import Field, SQLModel


class User(SQLModel, table=True):
    __tablename__ = "users"
    __table_args__ = {"schema": "siaga"}
    id: UUID = Field(default_factory=uuid4, primary_key=True)
    email: str = Field(sa_column=Column(Text, nullable=False))
    display_name: str = Field(sa_column=Column(Text, nullable=False))
    password_hash: str = Field(sa_column=Column(Text, nullable=False))
    role: str = "citizen"
    active: bool = True
    last_notification_sequence: int = Field(default=0, sa_column=Column(BigInteger, nullable=False))
    created_at: datetime = Field(sa_column=Column(DateTime(timezone=True), nullable=False))
    updated_at: datetime = Field(sa_column=Column(DateTime(timezone=True), nullable=False))
