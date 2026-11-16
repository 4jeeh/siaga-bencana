from datetime import UTC, datetime
from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url

BACKEND_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BACKEND_ROOT / ".env", extra="ignore")
    app_mode: Literal["production_live", "local_live", "simulation"] = "local_live"
    database_url: SecretStr
    runtime_db_role: str = "siaga_runtime"
    jwt_secret: SecretStr
    jwt_issuer: str = Field(default="siaga-bencana", min_length=1)
    jwt_audience: str = Field(default="siaga-mobile", min_length=1)
    jwt_ttl_seconds: int = Field(default=3600, ge=3600, le=3600)
    media_signing_secret: SecretStr
    storage_backend: Literal["local", "supabase"] = "local"
    storage_root: Path = Path(".storage/local_live")
    local_storage_dir: Path | None = None
    storage_bucket: str = ""
    supabase_url: str = ""
    supabase_service_key: SecretStr = SecretStr("")
    simulation_clock: str = ""
    bmkg_sync_enabled: bool = False
    sync_interval_seconds: int = 300
    cors_origins: list[str] = []

    @model_validator(mode="after")
    def validate_environment(self):
        for value in (self.jwt_secret, self.media_signing_secret):
            if len(value.get_secret_value().encode()) < 32:
                raise ValueError("Provide independent random secrets of at least 32 bytes")
        if self.jwt_secret == self.media_signing_secret:
            raise ValueError("JWT and media keys must differ")
        url = make_url(self.database_url.get_secret_value())
        if url.drivername != "postgresql+psycopg" or url.username != self.runtime_db_role:
            raise ValueError("DATABASE_URL must use psycopg and the configured runtime role")
        if self.local_storage_dir is not None:
            if (
                "storage_root" in self.model_fields_set
                and self.storage_root != self.local_storage_dir
            ):
                raise ValueError("Storage directory settings disagree")
            self.storage_root = self.local_storage_dir
        self.storage_root = (BACKEND_ROOT / self.storage_root).absolute()
        if self.app_mode == "simulation":
            clock = datetime.fromisoformat(self.simulation_clock.replace("Z", "+00:00"))
            if clock.tzinfo is None or clock.utcoffset().total_seconds() != 0:
                raise ValueError("SIMULATION_CLOCK must have UTC timezone")
            if not (url.database or "").endswith("_simulation"):
                raise ValueError("Simulation needs an isolated _simulation database")
            if self.storage_root.name != "simulation" or self.bmkg_sync_enabled:
                raise ValueError("Simulation needs isolated storage and disabled live sync")
        elif self.simulation_clock:
            raise ValueError("Live mode cannot use SIMULATION_CLOCK")
        if self.app_mode == "production_live":
            if not url.password or url.query.get("sslmode") not in ("require", "verify-full"):
                raise ValueError("Production database requires password and TLS")
        return self

    def domain_now(self) -> datetime:
        if self.app_mode == "simulation":
            return datetime.fromisoformat(self.simulation_clock.replace("Z", "+00:00"))
        return datetime.now(UTC)
