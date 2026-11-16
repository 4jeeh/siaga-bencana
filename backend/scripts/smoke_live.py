"""Actual Flutter client -> localhost Uvicorn -> disposable PostgreSQL; cleans up."""

import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from uuid import uuid4

import httpx
import psycopg
import uvicorn
from psycopg import sql

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
from app.core.config import Settings  # noqa: E402
from app.db.migrations import apply_migrations  # noqa: E402
from app.main import create_app  # noqa: E402


def main():
    name = f"siaga_test_{uuid4().hex}"
    admin_dsn = "postgresql://postgres@127.0.0.1:54329/postgres?connect_timeout=3"
    with psycopg.connect(admin_dsn, autocommit=True) as admin:
        admin.execute(sql.SQL("CREATE DATABASE {} OWNER siaga_owner").format(sql.Identifier(name)))
    try:
        apply_migrations(f"postgresql://siaga_owner@127.0.0.1:54329/{name}")
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        with tempfile.TemporaryDirectory(prefix="smoke_", dir=ROOT / "backend/.localdb") as temp:
            settings = Settings(
                _env_file=None,
                app_mode="local_live",
                database_url=f"postgresql+psycopg://siaga_runtime@127.0.0.1:54329/{name}",
                jwt_secret=secrets.token_urlsafe(48),
                media_signing_secret=secrets.token_urlsafe(48),
                storage_root=temp,
            )
            server = uvicorn.Server(
                uvicorn.Config(
                    create_app(settings),
                    host="127.0.0.1",
                    port=port,
                    proxy_headers=False,
                    log_level="warning",
                )
            )
            thread = threading.Thread(target=server.run, daemon=True)
            thread.start()
            try:
                url = f"http://127.0.0.1:{port}/api/v1"
                deadline = time.monotonic() + 15
                with httpx.Client(timeout=1, trust_env=False) as client:
                    while time.monotonic() < deadline:
                        try:
                            if client.get(url + "/ready").status_code == 200:
                                break
                        except httpx.TransportError:
                            pass
                        time.sleep(0.2)
                    else:
                        raise RuntimeError("Local smoke API did not become ready")
                flutter_bin = shutil.which("flutter") or shutil.which("flutter.bat")
                flutter_cmd = (
                    [flutter_bin]
                    if flutter_bin
                    else [sys.executable, str(ROOT / "scripts/flutter_local.py")]
                )
                return subprocess.run(
                    [
                        *flutter_cmd,
                        "test",
                        "--no-pub",
                        "test/live_smoke.dart",
                        f"--dart-define=LIVE_API_URL={url}",
                    ],
                    cwd=ROOT / "mobile",
                    check=False,
                    timeout=180,
                ).returncode
            finally:
                server.should_exit = True
                thread.join(timeout=15)
                if thread.is_alive():
                    raise RuntimeError("Smoke API did not shut down")
    finally:
        assert name.startswith("siaga_test_") and len(name) == 43
        with psycopg.connect(admin_dsn, autocommit=True) as admin:
            admin.execute(sql.SQL("DROP DATABASE {} WITH (FORCE)").format(sql.Identifier(name)))
        print("Smoke API stopped; isolated PostgreSQL database removed.")


if __name__ == "__main__":
    sys.exit(main())
