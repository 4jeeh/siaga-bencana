import gzip
import json
import secrets
import time
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import httpx
import psycopg
import pytest
from psycopg import sql
from sqlalchemy import event as sqlalchemy_event
from sqlalchemy import text
from sqlmodel import Session, select

from app.core.config import Settings
from app.db.migrations import apply_migrations
from app.db.session import make_engine
from app.models.alert_zone import AlertZone
from app.models.disaster_event import AreaPolygon, DisasterEvent, EventArea, EventReference
from app.models.notification_log import NotificationLog
from app.models.sync_run import SyncRun
from app.models.user import User
from app.services import bmkg_sync as worker
from app.services.bmkg_batch import Batch
from app.services.bmkg_events import notify
from app.services.bmkg_fetch import MAX_BYTES, open_fetcher
from app.services.bmkg_parser import CAP, NOWCAST, RSS, TEWS, TEWS_URLS, Record, xml_root
from tests.conftest import ADMIN_DSN

NOW = datetime(2030, 1, 1, tzinfo=UTC)
STAMP = NOW.isoformat()
END = (NOW + timedelta(hours=1)).isoformat()


@pytest.fixture(scope="module")
def bmkg_database():
    # Isolate worker notify() locks from committed users created by API/zone test modules.
    name = f"siaga_test_{uuid4().hex}"
    with psycopg.connect(ADMIN_DSN, autocommit=True) as admin:
        for role in ("siaga_owner", "siaga_runtime"):
            if not admin.execute("SELECT 1 FROM pg_roles WHERE rolname=%s", (role,)).fetchone():
                admin.execute(sql.SQL("CREATE ROLE {} LOGIN").format(sql.Identifier(role)))
        admin.execute(sql.SQL("CREATE DATABASE {} OWNER siaga_owner").format(sql.Identifier(name)))
    owner = f"postgresql://siaga_owner@127.0.0.1:54329/{name}?connect_timeout=3"
    runtime = f"postgresql://siaga_runtime@127.0.0.1:54329/{name}?connect_timeout=3"
    try:
        apply_migrations(owner)
        yield runtime
    finally:
        with psycopg.connect(ADMIN_DSN, autocommit=True) as admin:
            admin.execute(sql.SQL("DROP DATABASE {} WITH (FORCE)").format(sql.Identifier(name)))


@pytest.fixture
def settings(bmkg_database, tmp_path):
    return Settings(
        _env_file=None,
        database_url=bmkg_database.replace("postgresql:", "postgresql+psycopg:"),
        jwt_secret=secrets.token_urlsafe(48),
        media_signing_secret=secrets.token_urlsafe(48),
        storage_root=tmp_path / "private",
    )


@pytest.fixture
def db(settings, monkeypatch):
    monkeypatch.setattr(type(settings), "domain_now", lambda self: NOW)
    engine = make_engine(settings)
    # Worker transactions become independent SAVEPOINTs. Roll back test rows at teardown.
    try:
        with engine.connect() as conn:
            tx = conn.begin()
            conn.begin_nested()
            try:
                yield conn
            finally:
                tx.rollback()
    finally:
        engine.dispose()


def quake(offset=0, **fields):
    return {
        "DateTime": (NOW + timedelta(seconds=offset)).isoformat(),
        "Coordinates": "0,0",
        **fields,
    }


def quakes(rows):
    return json.dumps({"Infogempa": {"gempa": rows}}).encode()


def client_for(handler, **kwargs):
    return open_fetcher(
        transport=httpx.MockTransport(handler),
        resolver=kwargs.pop("resolver", lambda host: ["8.8.8.8"]),
        sleeper=kwargs.pop("sleeper", lambda delay: None),
        **kwargs,
    )


def cycle(db, settings, source, pages):
    def handler(request):
        content = pages.get(str(request.url))
        return httpx.Response(503) if content is None else httpx.Response(200, content=content)

    with client_for(handler) as fetcher:
        return worker.sync_source(db, settings, source, fetcher)


def latest_run(session, source):
    return session.exec(worker.latest(source)).one()


def zones(db, count):
    ids = sorted([uuid4() for _ in range(count)], reverse=True)
    with Session(db) as session, session.begin():
        for key in ids:
            user = User(
                id=key,
                email=f"{key}@example.test",
                display_name="Test",
                password_hash="$argon2id$test-only",
                created_at=NOW,
                updated_at=NOW,
            )
            session.add(user)
            session.flush()
            session.add(
                AlertZone(
                    user_id=key,
                    latitude=0,
                    longitude=0,
                    radius_km=25,
                    zone_version=1,
                    alert_eligible_since=NOW - timedelta(minutes=5),
                    notify_earthquake=True,
                    notify_weather=True,
                    created_at=NOW - timedelta(minutes=5),
                    updated_at=NOW,
                )
            )
    return ids


def test_lease_conflict_abandon_and_fence(db, settings):
    with db.engine.begin() as other:
        other.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": worker.LOCK_KEYS[TEWS]})
        assert worker.claim_lease(db, TEWS) is None
    old = worker.claim_lease(db, TEWS)
    assert worker.claim_lease(db, TEWS) is None
    with Session(db) as session, session.begin():
        run = session.get(SyncRun, old.id)
        run.started_at -= timedelta(minutes=10)
        run.lease_until = datetime.now(UTC) - timedelta(seconds=1)
    new = worker.claim_lease(db, TEWS)
    assert old.lease_token != new.lease_token
    with pytest.raises(worker.LostLease):
        worker.write_batch(db, old, Batch(), settings)
    with pytest.raises(worker.LostLease):
        worker.write_batch(
            db, new.model_copy(update={"lease_token": old.lease_token}), Batch(), settings
        )
    with Session(db) as session:
        assert session.get(SyncRun, old.id).status == "abandoned"
        assert session.get(SyncRun, new.id).status == "running"


def test_merge_freshness_and_fetch_failures(db, settings):
    pages = dict(
        zip(
            TEWS_URLS,
            [
                quakes(quake(Magnitude="5", Wilayah="A", Kedalaman="12 km")),
                quakes([quake(Magnitude="6", Potensi="P")]),
                quakes([quake(Dirasakan="III", Potensi="Q", Shakemap="a.jpg")]),
            ],
            strict=True,
        )
    )
    assert cycle(db, settings, TEWS, pages) == "success"
    pages[TEWS_URLS[0]] = quakes(quake(Magnitude="5", Wilayah="-"))
    assert cycle(db, settings, TEWS, pages) == "success"
    with Session(db) as session:
        row = session.exec(select(DisasterEvent)).one()
        assert (row.magnitude, row.depth_km, row.region, row.potential, row.felt) == (
            5,
            12,
            "A",
            "P",
            "III",
        )
        assert row.shakemap_url.endswith("/DataMKG/TEWS/a.jpg")
        assert row.content_version == 1
        success = latest_run(session, TEWS).last_success_at
    del pages[TEWS_URLS[2]]
    pages[TEWS_URLS[0]] = quakes(quake(Magnitude="7"))
    assert cycle(db, settings, TEWS, pages) == "partial"
    assert cycle(db, settings, TEWS, {}) == "failed"
    with Session(db) as session:
        assert latest_run(session, TEWS).last_success_at == success
        row = session.exec(select(DisasterEvent)).one()
        assert (row.magnitude, row.felt, row.content_version) == (7, "III", 2)
        fresh = worker.source_freshness(session, success + timedelta(minutes=15))
        assert [(f["source"], f["state"]) for f in fresh] == [
            (TEWS, "degraded"),
            (NOWCAST, "unavailable"),
        ]
        assert (
            worker.source_freshness(session, success + timedelta(minutes=16))[0]["state"] == "stale"
        )


@pytest.mark.parametrize(
    "body",
    [
        b"<!DoCtYpE rss><rss/>",
        b"<!ENTITY x 'x'><rss/>",
        b"<rss>\xff</rss>",
        b"<a>" * 33 + b"</a>" * 33,
        b"<a>" + b"<v/>" * 50000 + b"</a>",
        b" " * (MAX_BYTES + 1),
        "<rss/>".encode("utf-16-le"),
        f'<polygon xmlns="{CAP[1:-1]}">{"0,0 " * 10001}</polygon>'.encode(),
    ],
)
def test_xml_limits(body):
    with pytest.raises(ValueError):
        xml_root(body)


@pytest.mark.parametrize(
    "target",
    [
        "http://data.bmkg.go.id/a",
        "https://localhost/a",
        "https://127.0.0.1/a",
        "https://192.168.1.1/a",
    ],
)
def test_redirect_checked_before_second_request(target):
    seen = []

    def handler(request):
        seen.append(str(request.url))
        return httpx.Response(302, headers={"Location": target})

    with client_for(handler) as fetcher, pytest.raises(ValueError):
        fetcher.get(RSS, time.monotonic() + 30)
    assert seen == [RSS]


def test_private_dns_and_bounded_decompression():
    def handler(request):
        return httpx.Response(
            200,
            headers={"Content-Encoding": "gzip"},
            stream=httpx.ByteStream(gzip.compress(b"x" * (MAX_BYTES + 1))),
        )

    with client_for(handler, resolver=lambda host: ["8.8.8.8", "169.254.1.1"]) as fetcher:
        with pytest.raises(ValueError, match="Non-public"):
            fetcher.get(RSS, time.monotonic() + 30)
    with client_for(handler) as fetcher, pytest.raises(ValueError, match="too large"):
        fetcher.get(RSS, time.monotonic() + 30)


def test_fetch_retry_backoff():
    delays = []
    with client_for(lambda req: httpx.Response(503), sleeper=delays.append) as fetcher:
        with pytest.raises(httpx.HTTPStatusError):
            fetcher.get(RSS, time.monotonic() + 30)
    assert delays == [2, 4]


def cap(key, kind="Alert", refs="", status="Actual", severity="Extreme"):
    return f"""<alert xmlns="{CAP[1:-1]}"><identifier>{key}</identifier><sender>BMKG</sender>
        <sent>{STAMP}</sent><msgType>{kind}</msgType><status>{status}</status>
        <references>{refs}</references><info><language>en</language></info>
        <info><language>id-ID</language><event>Hujan</event><severity>{severity}</severity>
        <expires>{END}</expires><area><areaDesc>A</areaDesc>
        <polygon>-1,-1 1,-1 0,1</polygon><polygon>0,1</polygon></area></info></alert>""".encode()


def feed(documents, revision=1):
    pages = {}
    items = []
    for key, body in documents.items():
        link = f"https://www.bmkg.go.id/alerts/{key}_alert.xml"
        items.append(f"<item><link>{link}</link><guid>{key}</guid><title>{revision}</title></item>")
        pages[link] = body
    pages[RSS] = ("<rss><channel>" + "".join(items) + "</channel></rss>").encode()
    return pages


def test_cap_backlog_and_resume(db, settings):
    zones(db, 1)
    pages = feed({str(i): cap(str(i)) for i in range(51)})
    assert cycle(db, settings, NOWCAST, pages) == "partial"
    with Session(db) as session:
        run = latest_run(session, NOWCAST)
        assert not run.bootstrap_completed and run.last_success_at is None
        assert run.changed_count == 50
        assert worker.source_freshness(session, datetime.now(UTC))[1]["state"] == "degraded"
    # The deferred 51st link is still fetchable but has rotated out of RSS.
    pages[RSS] = feed({})[RSS]
    assert cycle(db, settings, NOWCAST, pages) == "success"
    with Session(db) as session:
        assert latest_run(session, NOWCAST).changed_count == 1
        assert len(session.exec(select(DisasterEvent)).all()) == 51
        assert not session.exec(select(NotificationLog)).all()


def test_cap_lifecycle_and_same_identifier_revision(db, settings):
    zones(db, 1)
    assert cycle(db, settings, NOWCAST, feed({"old": cap("old")})) == "success"
    docs = {
        "next": cap("next", "Update", f"BMKG,old,{STAMP}"),
        "missing": cap("missing", "Update", f"X,old,{STAMP}"),
        "test": cap("test", status="Test"),
        "exercise": cap("exercise", status="Exercise"),
        "bad": cap("bad", status="BAD"),
    }
    assert cycle(db, settings, NOWCAST, feed(docs)) == "partial"
    with Session(db) as session:
        events = {e.source_key: e for e in session.exec(select(DisasterEvent))}
        assert latest_run(session, NOWCAST).invalid_count == 1
        assert events["old"].superseded_at == NOW
        assert events["next"].lifecycle_complete and not events["missing"].lifecycle_complete
        assert session.exec(select(NotificationLog.event_id)).one() == events["next"].id
        refs = session.exec(select(EventReference)).all()
        assert {r.referenced_event_id for r in refs} == {None, events["old"].id}
    revised = {
        "next": cap("next", "Update", f"BMKG,old,{STAMP}", severity="Other"),
        "cancel": cap("cancel", "Cancel", f"BMKG,next,{STAMP}"),
    }
    assert cycle(db, settings, NOWCAST, feed(revised, 2)) == "success"
    with Session(db) as session:
        row = session.exec(select(DisasterEvent).where(DisasterEvent.source_key == "next")).one()
        assert (row.cancelled_at, row.content_version, row.severity) == (NOW, 2, "Unknown")
        assert (row.language, row.effective) == ("id-ID", NOW)
        area = session.exec(select(EventArea).where(EventArea.event_id == row.id)).one()
        polygons = session.exec(
            select(AreaPolygon).where(AreaPolygon.area_id == area.id).order_by(AreaPolygon.position)
        ).all()
        assert polygons[0].geometry_valid and polygons[1].invalid_reason
        assert polygons[1].centroid_latitude is None and polygons[1].west is None
        assert len(session.exec(select(NotificationLog)).all()) == 1


def test_atomic_bootstrap_ordered_locks_and_gapless_retry(db, settings):
    users = zones(db, 2)

    def pages(*offsets):
        return dict.fromkeys(TEWS_URLS, quakes([quake(i) for i in offsets]))

    assert cycle(db, settings, TEWS, pages(0)) == "success"
    assert cycle(db, settings, TEWS, pages(0, 1)) == "success"
    # Exercise the unique-log guard even if a writer presents the event twice.
    with Session(db) as session, session.begin():
        seen = session.exec(
            select(DisasterEvent).where(DisasterEvent.occurred_at == NOW + timedelta(seconds=1))
        ).one()
        notify(session, [(seen, Record({}, {}))], NOW)
    with Session(db) as session:
        checkpoint = latest_run(session, TEWS).checkpoint
    locks = []

    def fail_log(conn, cursor, statement, params, context, many):
        sql = " ".join(statement.lower().split())
        if "for update" in sql and "order by" in sql:
            locks.append(sql)
        if sql.startswith("insert into siaga.notification_logs"):
            # A real PostgreSQL statement failure aborts the current savepoint.
            cursor.execute("SELECT 1/0")

    sqlalchemy_event.listen(db, "before_cursor_execute", fail_log)
    try:
        assert cycle(db, settings, TEWS, pages(0, 1, 2)) == "failed"
    finally:
        sqlalchemy_event.remove(db, "before_cursor_execute", fail_log)
    assert "order by siaga.users.id" in locks[0]
    assert "order by siaga.alert_zones.user_id" in locks[1]
    with Session(db) as session:
        assert latest_run(session, TEWS).checkpoint == checkpoint
        assert len(session.exec(select(DisasterEvent)).all()) == 2
        assert len(session.exec(select(NotificationLog)).all()) == 2
        assert all(session.get(User, key).last_notification_sequence == 1 for key in users)
    assert cycle(db, settings, TEWS, pages(0, 1, 2)) == "success"
    assert cycle(db, settings, TEWS, pages(0, 1, 2)) == "success"
    with Session(db) as session:
        for key in users:
            assert session.exec(
                select(NotificationLog.sequence)
                .where(NotificationLog.user_id == key)
                .order_by(NotificationLog.sequence)
            ).all() == [1, 2]
            assert session.get(User, key).last_notification_sequence == 2


def test_late_cap_target_resolved_before_new_alert(db, settings):
    zones(db, 1)
    assert cycle(db, settings, NOWCAST, feed({})) == "success"
    cancel = cap("cancel-first", "Cancel", f"BMKG,late,{STAMP}")
    assert cycle(db, settings, NOWCAST, feed({"cancel": cancel})) == "success"
    assert cycle(db, settings, NOWCAST, feed({"late": cap("late")})) == "success"
    with Session(db) as session:
        target = session.exec(select(DisasterEvent).where(DisasterEvent.source_key == "late")).one()
        assert target.cancelled_at == NOW
        assert session.exec(select(EventReference.referenced_event_id)).one() == target.id
        assert not session.exec(select(NotificationLog)).all()
