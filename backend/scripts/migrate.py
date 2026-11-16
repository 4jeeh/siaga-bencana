"""Apply the locked ERD and runtime grants using MIGRATION_DATABASE_URL only."""

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.db.migrations import apply_migrations  # noqa: E402

if __name__ == "__main__":
    load_dotenv(Path(__file__).resolve().parents[1] / ".env")
    dsn = os.environ.get("MIGRATION_DATABASE_URL")
    if not dsn:
        sys.exit("Set MIGRATION_DATABASE_URL for the separate migration owner.")
    apply_migrations(dsn, os.environ.get("RUNTIME_DB_ROLE", "siaga_runtime"))
    print("Migration 0001_foundation and runtime grants verified.")
