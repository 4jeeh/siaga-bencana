"""Actual Flutter client -> localhost Uvicorn -> disposable PostgreSQL; cleans up."""

import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import httpx
import psycopg
import uvicorn
from psycopg import sql
from sqlmodel import Session

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
from app.core.config import Settings  # noqa: E402
from app.db.migrations import apply_migrations  # noqa: E402
from app.main import create_app  # noqa: E402
from app.models.disaster_event import DisasterEvent, EventReference  # noqa: E402
from app.services import radar  # noqa: E402
from app.services.bmkg_events import save_areas  # noqa: E402


def seed_smoke_events(engine, now: datetime) -> None:
    hour = timedelta(hours=1)
    quake_id = UUID("30000000-0000-4000-8000-000000000001")
    cap_id = UUID("30000000-0000-4000-8000-000000000002")
    prior_id = UUID("30000000-0000-4000-8000-000000000003")
    ring = radar.analyze_polygon([(-8, 179), (-8, -179), (-6, -179), (-6, 179)])
    with Session(engine) as session:
        session.add(
            DisasterEvent(
                id=quake_id,
                source="BMKG_TEWS",
                source_key="a" * 64,
                category="earthquake",
                title="Gempa Antimeridian Smoke",
                occurred_at=now - hour,
                latitude=-7.25,
                longitude=179.9,
                magnitude=5.2,
                depth_km=12.0,
                region="Pasifik Antimeridian",
                latitude_text="7.25 LS",
                longitude_text="179.90 BT",
                potential="Tidak berpotensi tsunami",
                source_url="https://data.bmkg.go.id/DataMKG/TEWS/autogempa.json",
                content_hash="1" * 64,
                first_seen_at=now - hour,
                last_seen_at=now,
                is_simulated=False,
            )
        )
        prior = DisasterEvent(
            id=prior_id,
            source="BMKG_NOWCAST",
            source_key="CAP-SMOKE-0",
            category="extreme_weather",
            title="Cuaca Sebelumnya Smoke",
            occurred_at=now - 2 * hour,
            source_url="https://www.bmkg.go.id/alerts/nowcast/id",
            sender="smoke@bmkg.go.id",
            sent=now - 2 * hour,
            status="Actual",
            msg_type="Alert",
            cap_event="Cuaca Ekstrem",
            severity="Moderate",
            urgency="Expected",
            certainty="Likely",
            effective=now - 2 * hour,
            expires=now + hour,
            superseded_at=now - hour,
            content_hash="2" * 64,
            first_seen_at=now - 2 * hour,
            last_seen_at=now - hour,
            is_simulated=False,
        )
        active = DisasterEvent(
            id=cap_id,
            source="BMKG_NOWCAST",
            source_key="CAP-SMOKE-1",
            category="extreme_weather",
            title="Cuaca Antimeridian Smoke",
            occurred_at=now - hour,
            latitude=ring.centroid_latitude,
            longitude=ring.centroid_longitude,
            source_url="https://www.bmkg.go.id/alerts/nowcast/id",
            sender="smoke@bmkg.go.id",
            sent=now - hour,
            status="Actual",
            msg_type="Update",
            cap_event="Cuaca Ekstrem",
            severity="Severe",
            urgency="Immediate",
            certainty="Observed",
            effective=now - hour,
            expires=now + 2 * hour,
            content_hash="3" * 64,
            first_seen_at=now - hour,
            last_seen_at=now,
            is_simulated=False,
        )
        session.add(prior)
        session.add(active)
        session.flush()
        save_areas(session, active, [("Pasifik Lintas Antimeridian", [ring])])
        session.add(
            EventReference(
                event_id=cap_id,
                relation_type="Update",
                referenced_source_key=prior.source_key,
                referenced_sender="smoke@bmkg.go.id",
                referenced_sent=now - 2 * hour,
                referenced_event_id=prior_id,
            )
        )
        session.commit()


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
            app = create_app(settings)
            seed_smoke_events(app.state.engine, datetime.now(UTC))
            server = uvicorn.Server(
                uvicorn.Config(
                    app,
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
