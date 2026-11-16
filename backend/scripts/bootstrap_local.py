"""Create missing dev DB/roles only on the disposable loopback cluster. No resets."""

import sys
from pathlib import Path

import psycopg
from psycopg import sql

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.db.migrations import apply_migrations  # noqa: E402


def bootstrap():
    with psycopg.connect("postgresql://postgres@127.0.0.1:54329/postgres", autocommit=True) as conn:
        for role in ("siaga_owner", "siaga_runtime"):
            if not conn.execute("SELECT 1 FROM pg_roles WHERE rolname=%s", (role,)).fetchone():
                conn.execute(
                    sql.SQL(
                        "CREATE ROLE {} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE "
                        "NOREPLICATION NOBYPASSRLS"
                    ).format(sql.Identifier(role))
                )
        if not conn.execute("SELECT 1 FROM pg_database WHERE datname='siaga_dev'").fetchone():
            conn.execute("CREATE DATABASE siaga_dev OWNER siaga_owner")
    apply_migrations("postgresql://siaga_owner@127.0.0.1:54329/siaga_dev")
    print("siaga_dev ready; migration owner and non-owner runtime are separate.")


if __name__ == "__main__":
    bootstrap()
