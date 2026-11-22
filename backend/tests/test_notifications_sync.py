import time
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from queue import Queue
from threading import Event
from uuid import UUID, uuid4

import psycopg
import pytest
from sqlalchemy import event as sqlalchemy_event
from sqlalchemy import text
from sqlmodel import Session, select

from app.core.config import Settings
from app.core.errors import ApiError
from app.models.alert_zone import AlertZone
from app.models.disaster_event import DisasterEvent
from app.models.notification_log import NotificationLog
from app.models.user import User
from app.repositories import notifications as repo
from app.schemas.notifications import MAX_SEQUENCE, parse_cursor_user_id, parse_sequence
from app.services import bmkg_events, bmkg_sync
from app.services.bmkg_batch import Batch
from app.services.bmkg_parser import TEWS, TEWS_URLS, parse_cap, parse_quake
from tests.conftest import isolated_database
from tests.test_api import error
from tests.test_bmkg_sync import NOW, cap, quake
from tests.test_zones import ZONE, put_zone

HISTORY = "/api/v1/me/notifications"
SYNC = HISTORY + "/sync"
LOCAL_ZONE = {**ZONE, "latitude": 0, "longitude": 0}


@pytest.fixture(scope="module")
def notification_database():
    with isolated_database() as db:
        yield db


@pytest.fixture
def database(notification_database):
    # notify() considers every active zone, and bootstrap state is per source.
    with psycopg.connect(notification_database["owner"]) as conn:
        conn.execute("TRUNCATE siaga.users, siaga.disaster_events, siaga.sync_runs CASCADE")
    return notification_database


@pytest.fixture
def clock(client, account, monkeypatch):
    times = [NOW - timedelta(minutes=5)]
    monkeypatch.setattr(Settings, "domain_now", lambda self: times[0])
    put_zone(client, account[2], LOCAL_ZONE)
    times[0] = NOW
    return times


def quakes(count):
    return [parse_quake(quake(i, Magnitude="4.5"), TEWS_URLS[0]) for i in range(count)]


def save_records(session, records):
    return [(bmkg_events.save_event(session, r, NOW, False)[0], r) for r in records]


def publish(app, records):
    with Session(app.state.engine) as session, session.begin():
        pairs = save_records(session, records)
        bmkg_events.notify(session, pairs, NOW)
        return [event.id for event, _ in pairs]


def get_json(client, path, headers, **params):
    response = client.get(path, headers=headers, params=params)
    assert response.status_code == 200, response.text
    return response.json()


def sequences(feed):
    return [item["sequence"] for item in feed["items"]]


def cursor(account, since):
    return {"cursor_user_id": account[1]["user"]["id"], "since_sequence": str(since)}


@pytest.mark.parametrize("raw", ["", "00", "01", "-1", "+1", " 1", "1\n", "١", "9" * 5000,
                                 str(MAX_SEQUENCE + 1)])
def test_bad_sequence(raw):
    with pytest.raises(ApiError) as exc:
        parse_sequence(raw, field="since_sequence")
    assert (exc.value.status, exc.value.code) == (422, "VALIDATION_ERROR")


def test_canonical_cursor_boundaries():
    owner = UUID("abcdef01-1111-2222-3333-0123456789ab")
    assert parse_cursor_user_id(str(owner), field="cursor_user_id") == owner
    assert parse_sequence("0", field="since_sequence") == 0
    assert parse_sequence(str(MAX_SEQUENCE), field="since_sequence") == MAX_SEQUENCE
    for raw in (str(owner).upper(), owner.hex, "{" + str(owner) + "}", str(owner) + "\n"):
        with pytest.raises(ApiError) as exc:
            parse_cursor_user_id(raw, field="cursor_user_id")
        assert (exc.value.status, exc.value.code) == (422, "VALIDATION_ERROR")


def test_cap_cutoff_uses_sent_and_strict_first_seen():
    record = parse_cap(cap("cutoff"), "https://www.bmkg.go.id/cutoff_alert.xml", {})
    event = DisasterEvent(**record.fields, first_seen_at=NOW + timedelta(seconds=1))
    zone = AlertZone(**LOCAL_ZONE, zone_version=1, alert_eligible_since=NOW)
    # Distinguish the two inputs at the service boundary (persisted CAPs have occurred_at=sent).
    event.occurred_at = NOW - timedelta(hours=1)
    assert bmkg_events.eligible_priority(event, record, zone, NOW) is not None
    event.occurred_at = NOW
    event.sent = NOW - timedelta(microseconds=1)
    assert bmkg_events.eligible_priority(event, record, zone, NOW) is None
    event.sent = NOW
    event.first_seen_at = NOW
    assert bmkg_events.eligible_priority(event, record, zone, NOW) is None


def test_bootstrap_then_new_and_replayed_batch(client, app, settings, account, clock):
    def run(records):
        lease = bmkg_sync.claim_lease(app.state.engine, TEWS)
        batch = Batch(records={r.fields["source_key"]: r for r in records})
        assert bmkg_sync.write_batch(app.state.engine, lease, batch, settings) == "success"

    records = quakes(2)
    run(records[:1])
    assert get_json(client, SYNC, account[2], baseline="true")["high_water_mark"] == 0
    run(records)
    run(records)
    feed = get_json(client, SYNC, account[2], **cursor(account, 0))
    assert feed["high_water_mark"] == 1
    assert sequences(feed) == [1]
    with Session(app.state.engine) as session:
        event = session.get(DisasterEvent, UUID(feed["items"][0]["event_id"]))
        assert event.source_key == records[1].fields["source_key"]


def test_baseline_and_ordered_catch_up(client, app, account, clock):
    records = quakes(5)
    # Equal occurrence times must use the event UUID as tie-breaker.
    records[-1] = parse_quake(quake(3, Coordinates="0.01,0"), TEWS_URLS[0])
    with Session(app.state.engine) as session, session.begin():
        pairs = sorted(save_records(session, records), key=lambda p: (p[0].occurred_at, p[0].id))
        expected_ids = [str(event.id) for event, _ in pairs]
        bmkg_events.notify(session, list(reversed(pairs)), NOW)

    headers = account[2]
    owner = account[1]["user"]["id"]
    baseline = get_json(client, SYNC, headers, baseline="true")
    assert baseline == dict(
        items=[], cursor_user_id=owner, high_water_mark=5, next_sequence=5,
        has_more=False, meta=baseline["meta"],
    )
    assert get_json(client, HISTORY, headers)["unread_count"] == 5
    since = 0
    received = []
    for expected, more in (([1, 2], True), ([3, 4], True), ([5], False), ([], False)):
        page = get_json(client, SYNC, headers, **cursor(account, since), limit=2, baseline="false")
        assert sequences(page) == expected
        assert page["high_water_mark"] == 5 and page["cursor_user_id"] == owner
        assert page["next_sequence"] == (expected[-1] if expected else since)
        assert page["has_more"] is more
        assert all(item["read_at"] is None for item in page["items"])
        received.extend(item["event_id"] for item in page["items"])
        since = page["next_sequence"]
    assert received == expected_ids


def test_history_lifecycle_and_zone_snapshot(client, app, account, clock):
    weather = [
        parse_cap(cap(key), f"https://www.bmkg.go.id/{key}_alert.xml", {})
        for key in ("cancelled", "superseded", "expires", "non_actual")
    ]
    quake_id, cancelled, superseded, expires, non_actual = publish(app, quakes(1) + weather)
    headers = account[2]
    initial = get_json(client, HISTORY, headers)
    assert sequences(initial) == [5, 4, 3, 2, 1]
    assert initial["unread_count"] == 5
    for item in initial["items"]:
        is_quake = item["event_id"] == str(quake_id)
        assert item["event_category"] == ("earthquake" if is_quake else "extreme_weather")
        assert item["current_lifecycle_status"] == ("current" if is_quake else "active")
        assert item["present_as_active_alert"] is True
        assert "user_id" not in item and item["priority_reasons"]

    with Session(app.state.engine) as session, session.begin():
        session.get(DisasterEvent, cancelled).cancelled_at = NOW
        session.get(DisasterEvent, superseded).superseded_at = NOW
        session.get(DisasterEvent, non_actual).status = "Test"
        session.get(DisasterEvent, expires).title = "Pembaruan peringatan"
    clock[0] += timedelta(minutes=1)
    zone = put_zone(client, headers, {**LOCAL_ZONE, "radius_km": 25})
    assert zone["zone_version"] == 2
    current = get_json(client, HISTORY, headers)
    by_event = {UUID(item["event_id"]): item for item in current["items"]}
    assert by_event[non_actual]["current_lifecycle_status"] == "active"
    assert by_event[non_actual]["present_as_active_alert"] is False
    assert by_event[expires]["title"] == "Pembaruan peringatan"
    clock[0] += timedelta(days=2)
    final = get_json(client, HISTORY, headers)
    statuses = {quake_id: "historical", cancelled: "cancelled", superseded: "superseded",
                expires: "expired", non_actual: "expired"}
    for before, after in zip(initial["items"], final["items"], strict=True):
        assert after["current_lifecycle_status"] == statuses[UUID(before["event_id"])]
        assert after["present_as_active_alert"] is False
        live_fields = {"title", "current_lifecycle_status", "present_as_active_alert"}
        for field in before.keys() - live_fields:
            assert before[field] == after[field]


def test_mark_read_and_unread_pagination(client, app, database, account, clock):
    publish(app, quakes(4))
    headers = account[2]
    first = get_json(client, HISTORY, headers, limit=2)
    assert sequences(first) == [4, 3]
    assert first["page"] == {"limit": 2, "offset": 0, "next_offset": 2, "has_more": True}
    assert first["unread_count"] == 4
    notification_id = first["items"][1]["id"]
    path = f"{HISTORY}/{notification_id}/read"
    baseline = get_json(client, SYNC, headers, baseline="true")
    with psycopg.connect(database["runtime"]) as conn:
        assert conn.execute("""
            SELECT current_user, has_column_privilege('siaga.notification_logs','read_at','UPDATE'),
                   has_column_privilege('siaga.notification_logs','sequence','UPDATE')
        """).fetchone() == ("siaga_runtime", True, False)

    clock[0] += timedelta(minutes=1)
    response = client.post(path, headers=headers, json={})
    assert response.status_code == 200, response.text
    read = response.json()["data"]
    assert read == {"id": notification_id, "read_at": "2030-01-01T00:01:00Z"}
    clock[0] += timedelta(minutes=3)
    replay = client.post(path, headers=headers, json={})
    assert replay.status_code == 200 and replay.json()["data"] == read
    second = get_json(client, HISTORY, headers, unread_only="true", limit=2, offset=2)
    assert sequences(second) == [1]
    assert second["page"] == {"limit": 2, "offset": 2, "next_offset": None, "has_more": False}
    assert second["unread_count"] == 3
    assert sequences(get_json(client, HISTORY, headers, unread_only="true")) == [4, 2, 1]
    after = get_json(client, SYNC, headers, baseline="true")
    assert after["next_sequence"] == after["high_water_mark"] == baseline["high_water_mark"] == 4
    catch_up = get_json(client, SYNC, headers, **cursor(account, 2))
    assert sequences(catch_up) == [3, 4] and catch_up["items"][0]["read_at"] == read["read_at"]

    other = client.post("/api/v1/auth/register", json={
        **account[0], "email": f"{uuid4()}@example.test",
    })
    assert other.status_code == 201, other.text
    other_headers = {"Authorization": "Bearer " + other.json()["data"]["access_token"]}
    isolated = get_json(client, HISTORY, other_headers)
    assert isolated["items"] == [] and isolated["unread_count"] == 0
    mismatch = client.get(SYNC, headers=other_headers, params=cursor(account, 4))
    error(mismatch, 409, "CURSOR_USER_MISMATCH")
    assert mismatch.json()["details"] == {"action": "fetch_baseline"}
    error(client.post(path, headers=other_headers, json={}), 404, "RESOURCE_NOT_FOUND")
    error(client.post(path, headers=headers, content="{}"), 415, "UNSUPPORTED_MEDIA_TYPE")
    error(client.post(path, headers=headers, json={"read_at": None}), 422, "VALIDATION_ERROR")
    error(client.post(path, headers={**headers, "Content-Type": "application/json"}, content="{"),
          400, "MALFORMED_REQUEST")
    for endpoint in (HISTORY, SYNC):
        error(client.request("GET", endpoint, headers=headers, json={}), 400, "MALFORMED_REQUEST")


def test_query_errors(client, account):
    valid = cursor(account, 0)
    invalid = [
        {}, {"baseline": "false"}, {"since_sequence": "0"},
        {"cursor_user_id": valid["cursor_user_id"]},
        *({"baseline": "true", key: value} for key, value in {**valid, "limit": "1"}.items()),
        *({**valid, "since_sequence": s} for s in ("01", "00", "-1", str(MAX_SEQUENCE + 1))),
        *({**valid, "cursor_user_id": s} for s in ("ABCDEF01-1111-2222-3333-0123456789AB", "x")),
        *({**valid, "baseline": s} for s in ("True", "0", "1", "")),
        *({**valid, "limit": s} for s in ("0", "51", "01", "-1", "1.5", "")),
    ]
    for params in invalid:
        error(client.get(SYNC, params=params, headers=account[2]), 422, "VALIDATION_ERROR")
    for params in ({"limit": 51}, {"offset": -1}, {"unread_only": "yes"}):
        error(client.get(HISTORY, params=params, headers=account[2]), 422, "VALIDATION_ERROR")
    for path in (HISTORY, SYNC + "?baseline=true"):
        error(client.get(path), 401, "AUTH_REQUIRED")
    error(client.post(f"{HISTORY}/{uuid4()}/read", json={}), 401, "AUTH_REQUIRED")


def test_cursor_conflicts_and_gap(client, app, database, account, clock, caplog):
    publish(app, quakes(4))
    headers = account[2]
    for owner, code in ((str(uuid4()), "CURSOR_USER_MISMATCH"),
                        (account[1]["user"]["id"], "CURSOR_OUT_OF_RANGE")):
        response = client.get(SYNC, headers=headers, params={
            "cursor_user_id": owner, "since_sequence": str(MAX_SEQUENCE),
        })
        error(response, 409, code)
        assert response.json()["details"] == {"action": "fetch_baseline"}
    with psycopg.connect(database["owner"]) as conn:
        deleted = conn.execute(
            "DELETE FROM siaga.notification_logs WHERE user_id=%s AND sequence=2",
            (account[1]["user"]["id"],),
        )
        assert deleted.rowcount == 1
    for limit in (2, 5):  # full page with a skipped number, then a short page
        response = client.get(SYNC, headers=headers, params={**cursor(account, 0), "limit": limit})
        error(response, 503, "SERVICE_UNAVAILABLE")
    assert f"notification_gap user_id={account[1]['user']['id']} since=0 hwm=4" in caplog.text


def wait_for_lock(database, waiter, holder):
    with psycopg.connect(database["owner"], autocommit=True) as conn:
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            blockers = conn.execute("SELECT pg_blocking_pids(%s)", (waiter,)).fetchone()[0]
            if holder in blockers:
                return
            time.sleep(0.01)
    pytest.fail("PostgreSQL did not report the expected row-lock wait")


def test_concurrent_notify_and_sync_snapshot(client, app, account, clock, database, monkeypatch):
    engine = app.state.engine
    user_id = UUID(account[1]["user"]["id"])
    records = quakes(2)
    with Session(engine) as seed, seed.begin():
        ids = [event.id for event, _ in save_records(seed, records)]
    writer_pid = Queue()
    snapshot_ready = Event()
    writers_done = Event()
    read_hwm = repo.high_water_mark

    def competing_writer():
        with Session(engine) as session, session.begin():
            # Keep the pre-lock ORM instance alive while the first increment is uncommitted.
            user = session.get(User, user_id)
            assert user.last_notification_sequence == 0
            event = session.get(DisasterEvent, ids[1])
            writer_pid.put(session.execute(text("SELECT pg_backend_pid()")).scalar_one())
            bmkg_events.notify(session, [(event, records[1])], NOW)

    def pause_snapshot(session, owner):
        hwm = read_hwm(session, owner)
        assert hwm == 0
        assert session.execute(text("SHOW transaction_isolation")).scalar_one() == "repeatable read"
        assert session.execute(text("SHOW transaction_read_only")).scalar_one() == "on"
        snapshot_ready.set()
        assert writers_done.wait(10)
        # Both writes committed between the endpoint's counter and row queries.
        assert read_hwm(session, owner) == hwm
        assert not session.exec(
            select(NotificationLog.id).where(NotificationLog.user_id == owner)
        ).all()
        return hwm

    with ThreadPoolExecutor(max_workers=2) as pool:
        with Session(engine) as first:
            first_pid = first.execute(text("SELECT pg_backend_pid()")).scalar_one()
            bmkg_events.notify(first, [(first.get(DisasterEvent, ids[0]), records[0])], NOW)
            first.flush()
            second = pool.submit(competing_writer)
            wait_for_lock(database, writer_pid.get(timeout=5), first_pid)
            with monkeypatch.context() as patch:
                patch.setattr(repo, "high_water_mark", pause_snapshot)
                reader = pool.submit(get_json, client, SYNC, account[2], **cursor(account, 0))
                try:
                    assert snapshot_ready.wait(5)
                    first.commit()
                    second.result(timeout=5)
                finally:
                    writers_done.set()
                old = reader.result(timeout=5)

    assert sequences(old) == [] and old["high_water_mark"] == old["next_sequence"] == 0
    fresh = get_json(client, SYNC, account[2], **cursor(account, 0))
    assert sequences(fresh) == [1, 2]
    assert fresh["high_water_mark"] == fresh["next_sequence"] == 2
    assert [item["event_id"] for item in fresh["items"]] == list(map(str, ids))


def test_zone_put_contends_on_user_before_zone(client, app, account, clock, database):
    engine = app.state.engine
    locks = Queue()

    def record_lock(conn, db_cursor, statement, params, context, many):
        if "FOR UPDATE" in statement.upper():
            locks.put((conn.connection.driver_connection.info.backend_pid, statement))

    with ThreadPoolExecutor(max_workers=1) as pool, Session(engine) as writer:
        writer_pid = writer.execute(text("SELECT pg_backend_pid()")).scalar_one()
        bmkg_events.notify(writer, save_records(writer, quakes(1)), NOW)
        writer.flush()
        sqlalchemy_event.listen(engine, "before_cursor_execute", record_lock)
        try:
            changed = pool.submit(put_zone, client, account[2],
                                  {**LOCAL_ZONE, "notify_earthquake": False})
            put_pid, first_lock = locks.get(timeout=5)
            assert "FROM siaga.users" in first_lock
            wait_for_lock(database, put_pid, writer_pid)
            writer.commit()
            assert changed.result(timeout=5)["zone_version"] == 2
            pid, next_lock = locks.get(timeout=5)
            assert pid == put_pid and "FROM siaga.alert_zones" in next_lock
        finally:
            sqlalchemy_event.remove(engine, "before_cursor_execute", record_lock)

    clock[0] += timedelta(seconds=1)
    with Session(engine) as session, session.begin():
        record = quakes(2)[1]
        event, _, _ = bmkg_events.save_event(session, record, clock[0], False)
        bmkg_events.notify(session, [(event, record)], clock[0])
    history = get_json(client, HISTORY, account[2])
    assert sequences(history) == [1] and history["items"][0]["zone_version"] == 1
