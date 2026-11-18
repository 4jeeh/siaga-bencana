import json
import math
import secrets
import warnings
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import psycopg
import pytest
from sqlalchemy import text
from sqlalchemy.exc import SAWarning
from sqlalchemy.sql import FROM_LINTING
from sqlmodel import Session

from app.core.config import Settings
from app.models.disaster_event import DisasterEvent, EventReference
from app.models.sync_run import SyncRun
from app.repositories.events import event_candidates
from app.services import radar
from app.services.bmkg_events import save_areas
from tests.conftest import isolated_database

NOW = datetime(2026, 11, 16, 3, tzinfo=UTC)
EVENTS = "/api/v1/events"
MAP = "/api/v1/map/markers"
HOUR = timedelta(hours=1)


@pytest.fixture(scope="module")
def event_database():
    with isolated_database(simulation=True) as db:
        yield db


@pytest.fixture
def settings(event_database, tmp_path):
    # Only this module's random database is reset. Requests use ordinary committed
    # transactions through the real runtime role, including deferred report audit checks.
    with psycopg.connect(event_database["owner"]) as conn:
        conn.execute("TRUNCATE siaga.users, siaga.disaster_events, siaga.sync_runs CASCADE")
    return Settings(
        _env_file=None,
        database_url=event_database["runtime"].replace("postgresql:", "postgresql+psycopg:"),
        jwt_secret=secrets.token_hex(32),
        media_signing_secret=secrets.token_hex(32),
        app_mode="simulation",
        simulation_clock=NOW.isoformat(),
        storage_root=tmp_path / "simulation",
    )


@pytest.fixture
def db(app):
    with Session(app.state.engine, expire_on_commit=False) as session:
        yield session


def zone(client, headers, lon=0, radius=50):
    response = client.put(
        "/api/v1/me/zone",
        headers=headers,
        json=dict(
            latitude=0, longitude=lon, radius_km=radius, notify_earthquake=True, notify_weather=True
        ),
    )
    assert response.status_code == 200, response.text


@pytest.fixture
def headers(account, client):
    auth = account[2]
    zone(client, auth)
    return auth


def get(client, headers, path, **params):
    response = client.get(path, headers=headers, params=params)
    assert response.status_code == 200, response.text
    body = response.json()
    meta = body["meta"]
    assert datetime.fromisoformat(meta["server_time"]) == NOW
    assert meta["mode"] == "simulation" and meta["is_simulated"]
    assert [s["source"] for s in meta["sources"]] == ["BMKG_TEWS", "BMKG_NOWCAST"]
    return body


def event(db, title, **fields):
    weather = fields.get("category") == "extreme_weather"
    defaults = dict(
        source="BMKG_NOWCAST" if weather else "BMKG_TEWS",
        source_key=uuid4().hex * 2,
        category="earthquake",
        latitude=0,
        longitude=0,
        magnitude=5,
        occurred_at=NOW,
        source_url="https://www.bmkg.go.id/",
        first_seen_at=NOW,
        last_seen_at=NOW,
        content_hash="0" * 64,
        is_simulated=True,
    )
    if weather:
        sent = fields.get("sent", NOW)
        defaults.update(
            status="Actual",
            msg_type="Alert",
            sender="fixture@example.test",
            sent=sent,
            effective=sent,
            occurred_at=sent,
            expires=NOW + HOUR,
            severity="Severe",
            magnitude=None,
            latitude=None,
            longitude=None,
        )
    row = DisasterEvent(title=title, **(defaults | fields))
    db.add(row)
    return row


def cap(db, title, areas=(), **fields):
    first = next((p for _, polygons in areas for p in polygons if p.geometry_valid), None)
    row = event(
        db,
        title,
        category="extreme_weather",
        latitude=first.centroid_latitude if first else None,
        longitude=first.centroid_longitude if first else None,
        **fields,
    )
    db.flush()
    save_areas(db, row, areas)
    return row


def test_access_and_errors(client, account, db):
    paths = [EVENTS, f"{EVENTS}/{uuid4()}", MAP]
    for path in paths:
        anonymous = client.get(path)
        assert (anonymous.status_code, anonymous.json()["code"]) == (401, "AUTH_REQUIRED")
        missing = client.get(path, headers=account[2])
        assert missing.status_code == 409
        assert missing.json()["code"] == "ZONE_REQUIRED"
        assert missing.json()["details"] == {"action": "setup_zone"}

    zone(client, account[2])
    hidden = cap(db, "hidden", status="Test")
    db.commit()
    for path in [paths[1], f"{EVENTS}/{hidden.id}"]:
        response = client.get(path, headers=account[2])
        assert (response.status_code, response.json()["code"]) == (404, "RESOURCE_NOT_FOUND")
    for url in [
        EVENTS + "?sort=priority",
        EVENTS + "?category=extreme_weather&sort=priority",
        EVENTS + "?weather_status=all",
        EVENTS + "?limit=51",
        EVENTS + "?limit=0",
        EVENTS + "?offset=-1",
        EVENTS + "?category=flood",
        EVENTS + "?radius_only=maybe",
        EVENTS + "?other=1",
        MAP + "?limit=20",
        MAP + "?category=other",
        EVENTS + "/bad-id",
        "/api/v1/me?limit=2",
        paths[1] + "?category=earthquake",
    ]:
        response = client.get(url, headers=account[2])
        assert (response.status_code, response.json()["code"]) == (422, "VALIDATION_ERROR"), url
    for value in [
        "",
        "0,1,2",
        "1,2,3,4,5",
        "NaN,0,1,1",
        "0,-Inf,1,1",
        "false,0,1,1",
        "-181,0,1,1",
        "0,-91,1,1",
        "1,2,3,0",
    ]:
        response = client.get(MAP, params={"bbox": value}, headers=account[2])
        assert (response.status_code, response.json()["code"]) == (422, "VALIDATION_ERROR")
    for path in [EVENTS + "?limit=1&limit=2", MAP + "?x=1&x=1", "/api/v1/me?x=1&x=1"]:
        response = client.get(path, headers=account[2])
        assert (response.status_code, response.json()["code"]) == (400, "MALFORMED_REQUEST")


def test_frozen_priority_and_history(client, headers, db):
    scored = event(
        db, "scored", latitude=math.degrees(10 / radar.EARTH_RADIUS_KM), occurred_at=NOW - 2 * HOUR
    )
    missing = event(db, "missing magnitude", magnitude=None)
    old = event(db, "old", occurred_at=NOW - timedelta(days=7, microseconds=1))
    edge = event(db, "inclusive cutoff", occurred_at=NOW - timedelta(days=7))
    db.add(
        SyncRun(
            source="BMKG_TEWS",
            status="success",
            lease_until=NOW + HOUR,
            started_at=NOW,
            finished_at=NOW,
            last_success_at=NOW,
            bootstrap_completed=True,
        )
    )
    db.commit()
    body = get(client, headers, EVENTS, category="earthquake", sort="priority")
    assert set(body) == {"items", "page", "meta"}
    assert body["meta"]["sources"][0]["state"] == "healthy"
    assert [r["id"] for r in body["items"]] == [str(scored.id), str(edge.id), str(missing.id)]
    p = body["items"][0]["priority"]
    assert (p["priority_score"], p["priority_display"], p["priority_label"]) == (
        74.25,
        "74.3",
        "high",
    )
    assert p["zone_version"] == body["meta"]["zone_version"] == 1
    assert p["evaluated_at"] == body["meta"]["server_time"]
    assert body["items"][0]["cap"] is None
    p = body["items"][-1]["priority"]
    assert p["priority_score"] is None and p["priority_label"] == "unavailable"
    assert "missing_data" in [r["code"] for r in p["priority_reasons"]]
    data = get(client, headers, f"{EVENTS}/{old.id}")["data"]
    assert data["lifecycle_status"] == "historical"
    assert data["earthquake"]["magnitude"] == 5 and data["weather"] is None


def test_cap_geometry_lifecycle_and_viewport(client, headers, db):
    zone(client, headers, lon=179.9, radius=25)
    far = radar.analyze_polygon([(1, 10), (1, 11), (2, 11)])
    wrapped = radar.analyze_polygon([(-1, 179), (-1, -179), (1, -179), (1, 179)])
    invalid = radar.analyze_polygon([(0, 0)])
    areas = [("First", [invalid, far]), ("Dateline", [wrapped])]
    active = cap(db, "active", areas, msg_type="Update", sent=NOW - HOUR)
    prior = cap(db, "superseded", sent=NOW - 2 * HOUR, superseded_at=active.sent)
    near = radar.analyze_polygon([(0, -179.95), (0, -179.8), (1, -179.8)])
    cap(db, "near", [("near", [near])])
    cap(db, "without geometry")
    for title, fields in [
        ("expired", dict(sent=NOW - HOUR, expires=NOW)),
        ("scheduled", dict(effective=NOW + HOUR, expires=NOW + 2 * HOUR)),
        ("cancelled", dict(cancelled_at=NOW)),
        ("incomplete", dict(lifecycle_complete=False, expires=None)),
        ("hidden", dict(status="Test")),
    ]:
        cap(db, title, **fields)
    db.add(
        EventReference(
            event_id=active.id,
            relation_type="Update",
            referenced_source_key=prior.source_key,
            referenced_event_id=prior.id,
            referenced_sender="fixture@example.test",
            referenced_sent=NOW - 2 * HOUR,
        )
    )
    event(db, "across", longitude=-179.9)
    event(db, "outside", longitude=-179.8)
    db.commit()
    response = get(client, headers, EVENTS)
    items = {r["title"]: r for r in response["items"]}
    assert set(items) == {"active", "near", "across"}
    assert items["active"]["priority"]["match_method"] == "inside_polygon"
    assert items["near"]["priority"]["match_method"] == "near_polygon_sample"
    assert items["across"]["priority"]["match_distance_km"] == pytest.approx(22.239016, abs=1e-6)
    assert items["active"]["cap"]["area_descriptions"] == ["First", "Dateline"]
    for private in ("vertices", "provenance", "content_hash"):
        assert private not in str(response)
    all_weather = get(
        client, headers, EVENTS, category="extreme_weather", radius_only=False, weather_status="all"
    )["items"]
    assert [r["lifecycle_status"] for r in all_weather][:3] == ["active"] * 3
    assert len(all_weather) == 8
    for r in all_weather:
        title = r["title"]
        assert r["lifecycle_status"] == (
            "active" if title in ("near", "without geometry") else title
        )
        detail = get(client, headers, EVENTS + "/" + r["id"])["data"]
        assert all(detail[k] == value for k, value in r.items())
        if title == "without geometry":
            assert detail["priority"]["match_method"] == "no_geometry"
    data = get(client, headers, f"{EVENTS}/{active.id}")["data"]
    assert data["earthquake"] is None and data["weather"]["status"] == "Actual"
    assert [a["position"] for a in data["areas"]] == [1, 2]
    first, second = data["areas"][0]["polygons"]
    assert (first["position"], second["position"]) == (1, 2)
    assert first["vertices"] == [] and not first["geometry_valid"]
    assert all(
        first[k] is None
        for k in (
            "centroid_latitude",
            "centroid_longitude",
            "south",
            "north",
            "west",
            "east",
            "crosses_antimeridian",
        )
    )
    polygon = data["areas"][1]["polygons"][0]
    assert polygon["crosses_antimeridian"]
    assert [v["sequence"] for v in polygon["vertices"]] == [1, 2, 3, 4, 5]
    assert data["references"] == [
        dict(
            relation_type="Update",
            referenced_source_key=prior.source_key,
            referenced_event_id=str(prior.id),
        )
    ]
    assert {r["title"] for r in get(client, headers, MAP, bbox="179,-2,-179,2")["items"]} == {
        "near",
        "across",
    }
    assert [r["title"] for r in get(client, headers, MAP, bbox="9,0,12,3")["items"]] == ["active"]
    world = get(client, headers, MAP, radius_only=False, bbox="-180,-90,180,90")
    assert {r["title"] for r in world["items"]} == {"active", "near", "across", "outside"}


def test_pagination_after_exact_radius(client, headers, db):
    # Inside the SQL rectangle but outside the circle. These newer rows must not
    # take up page slots or prevent fetching later eligible candidates.
    for i in range(70):
        event(db, f"outside {i}", latitude=0.4, longitude=0.4)
    ids = [str(event(db, f"quake {i}", occurred_at=NOW - HOUR).id) for i in range(75)]
    db.commit()
    seen = []
    offset = 0
    for count in (20, 20, 20, 15):
        page = get(client, headers, EVENTS, offset=offset)
        assert len(page["items"]) == count
        seen.extend(r["id"] for r in page["items"])
        more = len(seen) < 75
        assert page["page"] == dict(
            limit=20, offset=offset, next_offset=offset + 20 if more else None, has_more=more
        )
        offset += count
    assert seen == sorted(ids, reverse=True)


def seed_reports(db, reporter_id):
    admin = db.execute(
        text("""
        INSERT INTO siaga.users (email, display_name, password_hash, role)
        VALUES ('admin@example.test', 'Admin', '$argon2-fixture', 'admin') RETURNING id
    """)
    ).scalar_one()
    categories = ["earthquake", "flood", "eruption", "extreme_weather", "haze_other"]
    rows = []
    for i in range(61):
        rows.append(
            dict(
                reporter=reporter_id,
                key=uuid4(),
                category=categories[i % 5],
                description=f"Laporan warga untuk pengujian {i}",
                stamp=NOW,
                lon=0 if i < 60 else 0.1,
            )
        )
    db.execute(
        text("""
        INSERT INTO siaga.citizen_reports
            (reporter_id,client_request_id,payload_hash,category,description,latitude,longitude,
             created_at,updated_at,is_simulated)
        VALUES (:reporter,:key,repeat('a',64),:category,:description,0,:lon,:stamp,:stamp,true)
    """),
        rows,
    )
    params = dict(admin=admin, now=NOW)
    db.execute(
        text("""
        UPDATE siaga.citizen_reports SET status='in_review', version=2, reviewer_id=:admin,
            claimed_at=:now WHERE longitude=0
    """),
        params,
    )
    audit = text("""
        INSERT INTO siaga.report_verifications
            (report_id,moderator_id,from_status,to_status,reason,resulting_version,created_at)
        SELECT id,reviewer_id,:previous,status,'Pengujian status laporan',version,:now
        FROM siaga.citizen_reports WHERE version=:version
    """)
    db.execute(audit, dict(previous="pending", version=2, now=NOW))
    db.execute(
        text("""
        UPDATE siaga.citizen_reports SET status='verified', version=3, decided_at=:now
        WHERE status='in_review'
    """),
        params,
    )
    db.execute(audit, dict(previous="in_review", version=3, now=NOW))
    return (
        db.execute(text("SELECT id FROM siaga.citizen_reports WHERE status='verified'"))
        .scalars()
        .all()
    )


def test_combined_marker_cap_and_categories(client, headers, db, account):
    ids = seed_reports(db, account[1]["user"]["id"])
    recent = [event(db, f"recent {i}", occurred_at=NOW + HOUR).id for i in range(10)]
    tied = [event(db, f"tied {i}").id for i in range(40)]
    for i in range(10):
        event(db, f"more distant {i}", occurred_at=NOW + HOUR, longitude=0.1)
    db.commit()
    result = get(client, headers, MAP)
    assert result["cap"] == 100 and result["truncated"] is True
    expected = sorted(recent, reverse=True) + sorted(tied + ids, reverse=True)[:90]
    assert [r["id"] for r in result["items"]] == list(map(str, expected))
    for r in result["items"]:
        if r["kind"] == "report":
            assert (r["source"], r["match_method"], r["priority_label"]) == (
                "CITIZEN",
                "point_distance",
                None,
            )
    official = get(client, headers, MAP, include_reports=False)
    assert len(official["items"]) == 60 and not official["truncated"]
    assert {r["kind"] for r in official["items"]} == {"event"}
    for category in ("earthquake", "flood", "eruption", "extreme_weather", "haze_other"):
        filtered = get(client, headers, MAP, category=category)
        assert len(filtered["items"]) == (72 if category == "earthquake" else 12)
        assert all(r["category"] == category for r in filtered["items"])
    viewport = get(client, headers, MAP, bbox="0.09,-1,0.11,1")
    assert len(viewport["items"]) == 10 and not viewport["truncated"]
    assert all(r["kind"] == "event" for r in viewport["items"])


def test_candidate_index_and_correlated_polygon_plan(db):
    box = radar.zone_bounding_box(0, 179.9, 25)
    # The tiny fixture normally favors sequential scans. Check index eligibility
    # explicitly and lint the same SQLAlchemy FROM clauses used by the API.
    db.execute(text("SET LOCAL enable_seqscan=off"))
    for category in ("earthquake", None):
        stmt = event_candidates(NOW, category, True, box)
        with warnings.catch_warnings():
            warnings.simplefilter("error", SAWarning)
            compiled = stmt.compile(
                dialect=db.bind.dialect,
                linting=FROM_LINTING,
                compile_kwargs={"literal_binds": True},
            )
        plan = (
            db.connection().exec_driver_sql("EXPLAIN (FORMAT JSON) " + str(compiled)).scalar_one()
        )
        if isinstance(plan, str):
            plan = json.loads(plan)
        nodes = [plan[0]["Plan"]]
        indexes = set()
        while nodes:
            node = nodes.pop()
            indexes.add(node.get("Index Name"))
            nodes.extend(node.get("Plans", []))
        assert indexes.intersection(
            {
                "disaster_events_feed_idx",
                "disaster_events_coordinates_idx",
                "disaster_events_time_idx",
                "disaster_events_cap_window_idx",
            }
        ), plan
