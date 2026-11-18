import secrets
from contextlib import contextmanager
from uuid import uuid4

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg import sql

from app.core.config import Settings
from app.db.migrations import apply_migrations
from app.main import create_app

ADMIN_DSN = "postgresql://postgres@127.0.0.1:54329/postgres?connect_timeout=3"


@contextmanager
def isolated_database(*, simulation=False):
    # Fixed loopback host, unpredictable test-only name. Never accepts a production DSN.
    name = f"siaga_test_{uuid4().hex}" + ("_simulation" if simulation else "")
    with psycopg.connect(ADMIN_DSN, autocommit=True) as admin:
        for role in ("siaga_owner", "siaga_runtime"):
            if not admin.execute("SELECT 1 FROM pg_roles WHERE rolname=%s", (role,)).fetchone():
                admin.execute(sql.SQL("CREATE ROLE {} LOGIN").format(sql.Identifier(role)))
        admin.execute(sql.SQL("CREATE DATABASE {} OWNER siaga_owner").format(sql.Identifier(name)))
    owner = f"postgresql://siaga_owner@127.0.0.1:54329/{name}?connect_timeout=3"
    runtime = f"postgresql://siaga_runtime@127.0.0.1:54329/{name}?connect_timeout=3"
    try:
        # Exercise optional Supabase-role revocations without altering real cluster roles.
        apply_migrations(owner)
        apply_migrations(owner)  # idempotent tracking, no duplicate DDL
        yield {"name": name, "owner": owner, "runtime": runtime}
    finally:
        assert name.removesuffix("_simulation").startswith("siaga_test_")
        assert len(name.removesuffix("_simulation")) == len("siaga_test_") + 32
        with psycopg.connect(ADMIN_DSN, autocommit=True) as admin:
            admin.execute(sql.SQL("DROP DATABASE {} WITH (FORCE)").format(sql.Identifier(name)))


@pytest.fixture(scope="session")
def database():
    with isolated_database() as db:
        yield db


@pytest.fixture
def settings(database, tmp_path):
    return Settings(
        _env_file=None,
        database_url=database["runtime"].replace("postgresql:", "postgresql+psycopg:"),
        jwt_secret=secrets.token_urlsafe(48),
        media_signing_secret=secrets.token_urlsafe(48),
        storage_root=tmp_path / "private",
    )


@pytest.fixture
def app(settings):
    return create_app(settings)


@pytest.fixture
def client(app):
    with TestClient(app, raise_server_exceptions=False) as client:
        yield client


@pytest.fixture
def account(client):
    body = {
        "email": f"warga-{uuid4().hex}@example.test",
        "password": "  Sandi panjang  ",
        "display_name": " Warga Demo ",
    }
    response = client.post("/api/v1/auth/register", json=body)
    assert response.status_code == 201, response.text
    data = response.json()["data"]
    return body, data, {"Authorization": "Bearer " + data["access_token"]}
