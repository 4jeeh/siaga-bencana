import math
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from io import BytesIO
from urllib.parse import parse_qs, urlencode, urlsplit
from uuid import UUID, uuid4

import psycopg
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import event
from sqlalchemy.exc import SQLAlchemyError
from sqlmodel import Session, select

from app.core.errors import ApiError
from app.core.security import DUMMY_HASH, issue_token
from app.models.citizen_report import CitizenReport, MediaCleanupJob, ReportVerification
from app.models.disaster_event import DisasterEvent
from app.repositories import reports as repository
from app.services import radar
from app.services.storage import sign_local_photo_url
from tests.conftest import isolated_database

REPORTS = "/api/v1/reports"
CLAIM_REASON = "Laporan diambil untuk ditinjau."
REASON = "Kondisi lapangan telah diperiksa."
PUBLIC = {
    "id", "source", "event_id", "category", "description", "latitude", "longitude",
    "status", "verified_at", "has_photo", "is_simulated", "created_at", "match_distance_km",
}
PRIVATE = PUBLIC | {
    "reporter_id", "reviewer_id", "version", "client_request_id", "payload_hash",
    "payload_hash_algo", "claimed_at", "decided_at", "latest_reason", "updated_at",
}


@pytest.fixture(scope="module")
def report_database():
    with isolated_database() as db:
        yield db


@pytest.fixture
def database(report_database):
    with psycopg.connect(report_database["owner"]) as conn:
        conn.execute(
            "TRUNCATE siaga.users, siaga.disaster_events, siaga.media_cleanup_jobs CASCADE"
        )
    return report_database


@pytest.fixture
def actor(database, settings):
    def create(role="citizen"):
        user_id = uuid4()
        with psycopg.connect(database["owner"]) as conn:
            conn.execute(
                "INSERT INTO siaga.users (id,email,display_name,password_hash,role) "
                "VALUES (%s,%s,'Pengguna',%s,%s)",
                (user_id, f"{user_id}@example.test", DUMMY_HASH, role),
            )
        token, _ = issue_token(user_id, settings)
        return {"Authorization": f"Bearer {token}"}

    return create


def fields(**overrides):
    return dict(
        client_request_id=str(uuid4()), category="flood", description="Air mulai memasuki jalan.",
        latitude="0", longitude="0",
    ) | overrides


def parts(values):
    return [(name, (None, value)) for name, value in values.items()]


def jpeg(color="red"):
    exif = Image.Exif()
    exif[274] = 6
    exif[270] = "private note"
    output = BytesIO()
    Image.new("RGB", (1600, 800), color).save(output, format="JPEG", exif=exif)
    return output.getvalue()


def submit(client, headers, values, photo=None):
    files = parts(values)
    if photo is not None:
        files.append(("photo", ("private-name.jpg", photo, "image/jpeg")))
    return client.post(REPORTS, headers=headers, files=files)


def success(response, status=200):
    assert response.status_code == status, response.text
    return response.json()


def error(response, status, code):
    assert response.status_code == status, response.text
    body = response.json()
    assert body["code"] == code
    assert body["request_id"] == response.headers["X-Request-ID"]
    return body["details"]


def created(response):
    row = success(response, 201)["data"]
    assert set(row) == PRIVATE
    assert row["version"] == 1 and row["status"] == "pending"
    assert response.headers["Idempotent-Replay"] == "false"
    assert response.headers["Location"] == f"{REPORTS}/{row['id']}"
    return response.headers["Location"]


def claim(client, headers, path, version=1):
    return client.post(path + "/claim", headers=headers, json={"expected_version": version})


def decide(client, headers, path, version=2, outcome="verified", reason=REASON):
    return client.post(path + "/decision", headers=headers, json=dict(
        expected_version=version, outcome=outcome, reason=reason,
    ))


def feed(client, headers, **query):
    return success(client.get(REPORTS, headers=headers, params=query))


def seed_event(app, status="Actual"):
    now = datetime.now(UTC)
    row = DisasterEvent(
        source="BMKG_NOWCAST", source_key=uuid4().hex, category="extreme_weather",
        title="Cuaca uji", source_url="https://example.test/", content_hash="0" * 64,
        first_seen_at=now, last_seen_at=now, occurred_at=now, sent=now, effective=now,
        expires=now + timedelta(hours=1), sender="test", status=status, msg_type="Alert",
    )
    with Session(app.state.engine) as session:
        event_id = row.id
        session.add(row)
        session.commit()
    return str(event_id)


def test_submit_replay_tracks_moderation(client, app, account, actor, monkeypatch):
    owner, admin = account[2], actor("admin")
    values = fields()
    def unexpected(*args):
        pytest.fail("A text-only submission accessed storage")

    monkeypatch.setattr(app.state.storage, "put_bytes", unexpected)
    path = created(submit(client, owner, values))
    for version in (1, 2, 3):
        if version == 2:
            success(claim(client, admin, path))
        if version == 3:
            success(decide(client, admin, path))
        response = submit(client, owner, values)
        data = success(response)["data"]
        assert response.headers["Idempotent-Replay"] == "true"
        assert data == success(client.get(path, headers=owner))["data"]
        assert data["version"] == version and not data["has_photo"]
    conflict = submit(client, owner, values | {"category": "eruption"})
    assert error(conflict, 409, "IDEMPOTENCY_CONFLICT") == {
        "client_request_id": values["client_request_id"]
    }
    limited = submit(client, owner, values)
    error(limited, 429, "RATE_LIMITED")
    assert int(limited.headers["Retry-After"]) >= 1


def test_private_photo_and_signed_download(client, app, account, actor, monkeypatch):
    owner, other, admin = account[2], actor(), actor("admin")
    raw = jpeg() + bytes(1_048_576)  # Valid JPEG, between the 1 MiB and 2 MiB boundaries.
    values = fields()
    path = created(submit(client, owner, values, raw))
    photo_url = path + "/photo-url"
    error(client.get(path, headers=other), 404, "RESOURCE_NOT_FOUND")
    error(client.get(photo_url, headers=other), 404, "RESOURCE_NOT_FOUND")
    error(client.get(photo_url), 401, "AUTH_REQUIRED")
    with Session(app.state.engine) as session:
        row = session.exec(select(CitizenReport)).one()
        key, report_id = row.photo_object_key, row.id
        assert (row.photo_width, row.photo_height) == (512, 1024)
    signed = success(client.get(photo_url, headers=owner))["data"]
    assert signed["expires_in"] == 300 and signed["content_type"] == "image/jpeg"
    assert not signed["is_simulated"]
    url = urlsplit(signed["url"])
    params = {k: v[0] for k, v in parse_qs(url.query).items()}
    assert int(params["expires"]) == int(datetime.fromisoformat(signed["expires_at"]).timestamp())
    response = client.get(signed["url"])
    assert response.status_code == 200, response.text
    for name, value in {
        "Content-Type": "image/jpeg", "Content-Disposition": "inline",
        "X-Content-Type-Options": "nosniff", "Cache-Control": "no-store",
    }.items():
        assert response.headers[name] == value
    with Image.open(BytesIO(response.content)) as image:
        assert image.size == (512, 1024) and not image.getexif()
    assert response.content == app.state.storage.get_bytes(key)

    def unexpected(*args):
        pytest.fail("Replay wrote another photo")

    monkeypatch.setattr(app.state.storage, "put_bytes", unexpected)
    replay = submit(client, owner, values, raw)
    assert success(replay)["data"]["has_photo"] and replay.headers["Idempotent-Replay"] == "true"
    error(submit(client, owner, values, jpeg("blue")), 409, "IDEMPOTENCY_CONFLICT")

    for changes in ({"signature": "a" * 43}, {"expires": str(int(params["expires"]) - 1)}):
        error(client.get(url.path, params=params | changes), 403, "FORBIDDEN")
    expired, _, _ = sign_local_photo_url(
        "http://testserver", report_id, key, app.state.settings,
        now=datetime.now(UTC) - timedelta(minutes=6),
    )
    error(client.get(expired), 403, "FORBIDDEN")
    for invalid in ({}, params | {"expires": "1.5"}, params | {"signature": "!"}):
        error(client.get(url.path, params=invalid), 422, "VALIDATION_ERROR")
    error(client.get(url.path + "?" + urlencode(params) + "&expires=1"), 400, "MALFORMED_REQUEST")
    success(claim(client, admin, path))
    success(decide(client, admin, path))
    success(client.get(photo_url, headers=other))
    app.state.storage.delete_object(key)
    error(client.get(signed["url"]), 404, "PHOTO_NOT_FOUND")
    monkeypatch.setattr(app.state.settings, "storage_backend", "supabase")
    error(client.get(signed["url"]), 404, "RESOURCE_NOT_FOUND")
    error(client.get(url.path), 404, "RESOURCE_NOT_FOUND")


@pytest.mark.parametrize("name", [
    "reporter_id", "status", "reviewer_id", "version", "is_simulated", "payload_hash",
])
def test_forbidden_form_fields(client, account, name):
    error(submit(client, account[2], fields(**{name: "x"})), 422, "VALIDATION_ERROR")


@pytest.mark.parametrize("change", [
    {"event_id": ""}, {"event_id": "null"}, {"event_id": "not-a-uuid"}, {"photo": "not-file"},
])
def test_invalid_optional_parts(client, account, change):
    error(submit(client, account[2], fields(**change)), 422, "VALIDATION_ERROR")


def test_multipart_structure(client, account):
    owner = account[2]
    values = fields()
    missing = values.copy()
    del missing["description"]
    error(submit(client, owner, missing), 422, "VALIDATION_ERROR")
    photo = ("photo", ("image.jpg", jpeg(), "image/jpeg"))
    cases = [
        (parts(values) + [("category", (None, "flood"))], 400, "MALFORMED_REQUEST"),
        (parts(values) + [photo, photo], 400, "MALFORMED_REQUEST"),
        (parts(missing) + [("description", photo[1])], 422, "VALIDATION_ERROR"),
        (parts(values) + [("event_id", photo[1])], 422, "VALIDATION_ERROR"),
    ]
    for files, status, code in cases:
        error(client.post(REPORTS, headers=owner, files=files), status, code)


def test_media_types_limits_and_boundary(client, account):
    owner = account[2]
    error(client.post(REPORTS, headers=owner, json=fields()), 415, "UNSUPPORTED_MEDIA_TYPE")
    files = parts(fields()) + [("photo", ("x.png", b"\x89PNG", "image/png"))]
    error(client.post(REPORTS, headers=owner, files=files), 415, "UNSUPPORTED_MEDIA_TYPE")
    error(submit(client, owner, fields(), bytes(2_097_153)), 413, "REQUEST_TOO_LARGE")
    error(submit(client, owner, fields(), bytes(3_145_728)), 413, "REQUEST_TOO_LARGE")
    for content_type, body in (
        ("multipart/form-data", b"missing boundary"),
        ("multipart/form-data; boundary=B", b"--B\r\ntruncated"),
        ("multipart/form-data; boundary=B", b"--B\r\nbroken headers\r\n--B--\r\n"),
    ):
        headers = owner | {"Content-Type": content_type}
        response = client.post(REPORTS, headers=headers, content=body)
        error(response, 400, "MALFORMED_REQUEST")


def test_hidden_events_and_missing_photo(client, app, account, actor):
    owner, other = account[2], actor()
    for event_id in (str(uuid4()), seed_event(app, "Test")):
        error(submit(client, owner, fields(event_id=event_id)), 404, "RESOURCE_NOT_FOUND")
    path = created(submit(client, owner, fields()))
    error(client.get(path + "/photo-url", headers=owner), 404, "PHOTO_NOT_FOUND")
    error(client.get(path + "/photo-url", headers=other), 404, "RESOURCE_NOT_FOUND")
    unknown = f"{REPORTS}/{uuid4()}"
    for suffix in ("", "/photo-url", "/verifications"):
        error(client.get(unknown + suffix, headers=owner), 404, "RESOURCE_NOT_FOUND")


def test_storage_failure(client, app, account, monkeypatch):
    def fail(key, data):
        raise ApiError(503, "SERVICE_UNAVAILABLE", "Uji storage.")

    monkeypatch.setattr(app.state.storage, "put_bytes", fail)
    error(submit(client, account[2], fields(), jpeg()), 503, "SERVICE_UNAVAILABLE")
    with Session(app.state.engine) as session:
        assert not session.exec(select(CitizenReport)).all()
    assert not app.state.in_flight_uploads


@pytest.mark.parametrize("outcome", ["verified", "rejected"])
def test_moderation_precedence_and_audit(client, account, actor, outcome):
    owner, admin, other_admin, citizen = account[2], actor("admin"), actor("admin"), actor()
    path = created(submit(client, owner, fields()))
    own_report = created(submit(client, admin, fields()))
    error(claim(client, admin, own_report), 403, "SELF_REVIEW_FORBIDDEN")
    error(decide(client, admin, own_report), 403, "SELF_REVIEW_FORBIDDEN")
    error(claim(client, citizen, path), 403, "FORBIDDEN")
    error(decide(client, citizen, path, reason="x"), 403, "FORBIDDEN")
    missing = f"{REPORTS}/{uuid4()}"
    error(claim(client, admin, missing), 404, "RESOURCE_NOT_FOUND")
    error(decide(client, admin, missing), 404, "RESOURCE_NOT_FOUND")
    error(decide(client, admin, missing, reason="x"), 422, "VALIDATION_ERROR")
    initial = {"current_status": "pending", "current_version": 1}
    assert error(decide(client, admin, path), 409, "VERSION_CONFLICT") == initial
    assert error(claim(client, admin, path, 2), 409, "VERSION_CONFLICT") == initial
    history = path + "/verifications"
    assert success(client.get(history, headers=owner))["items"] == []
    claimed = success(claim(client, admin, path))["data"]
    assert claimed["version"] == 2 and claimed["status"] == "in_review"
    assert claimed["claimed_at"] and claimed["decided_at"] is None
    conflict = {"current_version": 2, "current_status": "in_review"}
    assert error(claim(client, admin, path), 409, "VERSION_CONFLICT") == conflict
    assert error(decide(client, other_admin, path, 1), 409, "VERSION_CONFLICT") == conflict
    error(decide(client, other_admin, path), 403, "CLAIM_NOT_OWNED")
    for reason in ("123456789", "a" * 501, REASON + "\x00"):
        error(decide(client, admin, path, reason=reason), 422, "VALIDATION_ERROR")
    final = success(decide(client, admin, path, outcome=outcome, reason="  Cafe\u0301 ditinjau.  "))
    assert final["data"] == claimed | {
        "status": outcome, "version": 3, "decided_at": final["data"]["decided_at"]
    }
    assert final["data"]["decided_at"] is not None
    assert error(decide(client, other_admin, path), 409, "VERSION_CONFLICT") == {
        "current_version": 3, "current_status": outcome
    }
    data = success(client.get(path, headers=owner))["data"]
    assert data["verified_at"] == (data["decided_at"] if outcome == "verified" else None)
    assert data["latest_reason"] == "Café ditinjau."
    for reader in (owner, admin, other_admin):
        first = success(client.get(history, headers=reader, params={"limit": 1}))
        assert first["page"] == dict(limit=1, offset=0, has_more=True, next_offset=1)
        second = success(client.get(history, headers=reader, params={"limit": 1, "offset": 1}))
        assert second["page"] == dict(limit=1, offset=1, has_more=False, next_offset=None)
        a, b = first["items"][0], second["items"][0]
        assert (a["from_status"], a["to_status"], a["resulting_version"], a["reason"]) == (
            "pending", "in_review", 2, CLAIM_REASON
        )
        assert (b["from_status"], b["to_status"], b["resulting_version"], b["reason"]) == (
            "in_review", outcome, 3, "Café ditinjau."
        )
        assert a["moderator_id"] == b["moderator_id"] == claimed["reviewer_id"]
        assert a["report_id"] == b["report_id"] == data["id"]
    error(client.get(history, headers=citizen), 404, "RESOURCE_NOT_FOUND")
    if outcome == "verified":
        assert set(success(client.get(path, headers=citizen))["data"]) == PUBLIC
    else:
        error(client.get(path, headers=citizen), 404, "RESOURCE_NOT_FOUND")


def test_moderation_protocol(client, account, actor):
    path = created(submit(client, account[2], fields()))
    admin = actor("admin")
    for action, extra in (("claim", {}), ("decision", {"outcome": "verified", "reason": REASON})):
        url = f"{path}/{action}"
        for version in (True, 1.0, "1", 0):
            response = client.post(url, headers=admin, json=extra | {"expected_version": version})
            error(response, 422, "VALIDATION_ERROR")
        for body in (b'{"expected_version":1,"expected_version":1}', b'{"expected_version":NaN}'):
            response = client.post(url, headers=admin | {"Content-Type": "application/json"},
                                   content=body)
            error(response, 400, "MALFORMED_REQUEST")
        error(client.post(url, headers=admin, data={"expected_version": 1}),
              415, "UNSUPPORTED_MEDIA_TYPE")
        error(client.post(url, headers=admin, json={"expected_version": 1, "extra": 1} | extra),
              422, "VALIDATION_ERROR")


def test_report_scopes_and_privacy(client, app, account, actor):
    owner, admin, other = account[2], actor("admin"), actor()
    event_id = seed_event(app)
    paths = [
        created(submit(client, owner, fields(event_id=event_id))),
        created(submit(client, owner, fields(category="eruption"))),
        created(submit(client, other, fields(event_id=event_id))),
    ]
    ids = [path.rsplit("/", 1)[1] for path in paths]
    error(client.get(REPORTS, headers=owner), 409, "ZONE_REQUIRED")
    error(client.get(REPORTS + "?scope=review", headers=owner), 403, "FORBIDDEN")
    for query in ("scope=review&status=rejected", "scope=review&status=verified",
                  "scope=nearby&status=pending", "scope=verified&status=rejected",
                  "limit=51", "offset=-1", "category=invalid", "extra=x"):
        error(client.get(REPORTS + "?" + query, headers=admin), 422, "VALIDATION_ERROR")
    error(client.get(paths[0] + "?scope=mine", headers=admin), 422, "VALIDATION_ERROR")
    error(client.get(paths[0] + "/verifications?offset=0&offset=0", headers=admin),
          400, "MALFORMED_REQUEST")
    success(claim(client, admin, paths[0]))
    page = feed(client, admin, scope="review", limit=2)
    assert [row["id"] for row in page["items"]] == ids[:2]
    assert page["page"] == dict(limit=2, offset=0, next_offset=2, has_more=True)
    assert page["items"][0]["latest_reason"] == CLAIM_REASON
    assert all(set(row) == PRIVATE for row in page["items"])
    tail = feed(client, admin, scope="review", offset=2, limit=2)
    assert [row["id"] for row in tail["items"]] == ids[2:]
    assert tail["page"]["next_offset"] is None
    assert [r["id"] for r in feed(client, admin, scope="review", status="in_review")["items"]] == [
        ids[0]
    ]
    success(decide(client, admin, paths[0]))
    success(claim(client, admin, paths[1]))
    success(decide(client, admin, paths[1]))
    mine = feed(client, owner, scope="mine")
    assert [r["id"] for r in mine["items"]] == [ids[1], ids[0]]
    assert all(set(r) == PRIVATE and r["latest_reason"] == REASON for r in mine["items"])
    assert not feed(client, owner, scope="mine", status="pending")["items"]
    related = feed(client, other, scope="verified", event_id=event_id, category="flood")
    assert [r["id"] for r in related["items"]] == [ids[0]]
    assert set(related["items"][0]) == PUBLIC and related["items"][0]["match_distance_km"] is None
    assert set(feed(client, owner, scope="verified")["items"][0]) == PRIVATE
    assert set(feed(client, admin, scope="verified")["items"][0]) == PRIVATE
    assert not feed(client, owner, scope="verified", event_id=str(uuid4()))["items"]
    success(claim(client, admin, paths[2]))
    success(decide(client, admin, paths[2]))
    mixed = feed(client, other, scope="verified", event_id=event_id)["items"]
    assert [r["id"] for r in mixed] == [ids[2], ids[0]]
    assert set(mixed[0]) == PRIVATE and set(mixed[1]) == PUBLIC


def test_nearby_radius_before_pagination(client, account, actor):
    owner, admin, reader = account[2], actor("admin"), actor()
    lat = math.degrees(25.0000005 / radar.EARTH_RADIUS_KM)
    success(client.put("/api/v1/me/zone", headers=reader, json=dict(
        latitude=lat, longitude=179.99, radius_km=25, notify_earthquake=True, notify_weather=True,
    )))
    # The first point needs the 1 mm tolerance. The second crosses the dateline.
    # The newest is inside the bounding box but outside the circle.
    ids = []
    for latitude, longitude in [("0", "179.99"), ("0.22", "-179.999"), ("0", "-179.999")]:
        path = created(submit(client, owner, fields(latitude=latitude, longitude=longitude)))
        success(claim(client, admin, path))
        success(decide(client, admin, path))
        ids.append(path.rsplit("/", 1)[1])
    for offset, expected in enumerate((ids[1], ids[0])):
        page = feed(client, reader, limit=1, offset=offset)
        assert page["meta"]["zone_version"] == 1
        row, = page["items"]
        assert row["id"] == expected and set(row) == PUBLIC
        assert radar.is_within_radius(row["match_distance_km"], 25)
        assert page["page"]["next_offset"] == (1 if offset == 0 else None)
        if offset:
            assert row["match_distance_km"] == pytest.approx(25.0000005, abs=1e-9)


def parallel_requests(app, send, inputs):
    start = threading.Barrier(2, timeout=10)

    def worker(value):
        # The client fixture owns app lifespan. Each worker opens its own HTTP client
        # and each request obtains its own session from the real engine pool.
        client = TestClient(app, raise_server_exceptions=False)
        try:
            start.wait()
            return send(client, value)
        finally:
            client.close()

    with ThreadPoolExecutor(max_workers=2) as pool:
        return list(pool.map(worker, inputs))


def test_concurrent_claim_locks_one_report(client, app, account, actor):
    path = created(submit(client, account[2], fields()))
    admins = [actor("admin"), actor("admin")]
    locking = threading.Barrier(2, timeout=10)
    connections = []

    def before_lock(conn, cursor, statement, parameters, context, executemany):
        if "FOR UPDATE" in statement and "siaga.citizen_reports" in statement:
            connections.append(conn.connection.driver_connection.info.backend_pid)
            locking.wait()

    event.listen(app.state.engine, "before_cursor_execute", before_lock)
    try:
        responses = parallel_requests(app, lambda c, h: claim(c, h, path), admins)
    finally:
        event.remove(app.state.engine, "before_cursor_execute", before_lock)
    assert len(set(connections)) == 2
    winner, loser = sorted(responses, key=lambda r: r.status_code)
    data = success(winner)["data"]
    assert data["status"] == "in_review" and data["version"] == 2
    assert error(loser, 409, "VERSION_CONFLICT") == {
        "current_version": 2, "current_status": "in_review"
    }
    with Session(app.state.engine) as session:
        audit = session.exec(select(ReportVerification)).one()
        assert str(audit.report_id) == data["id"] and audit.resulting_version == 2
        assert str(audit.moderator_id) == data["reviewer_id"]


@pytest.mark.parametrize("different,fail_delete", [(False, False), (True, False), (False, True)])
def test_concurrent_upload_cleans_only_loser(client, app, account, monkeypatch, different,
                                            fail_delete):
    storage = app.state.storage
    put = storage.put_bytes
    uploaded = threading.Barrier(2, timeout=10)

    def put_together(key, data):
        assert key in app.state.in_flight_uploads
        put(key, data)
        uploaded.wait()

    monkeypatch.setattr(storage, "put_bytes", put_together)
    if fail_delete:
        def fail(key):
            raise OSError("unavailable")

        monkeypatch.setattr(storage, "delete_object", fail)
    values = fields()
    raw = jpeg()
    photos = [raw, jpeg("blue") if different else raw]
    responses = parallel_requests(app, lambda c, p: submit(c, account[2], values, p), photos)
    first, second = sorted(responses, key=lambda r: r.headers.get("Idempotent-Replay") != "false")
    path = created(first)
    if different:
        error(second, 409, "IDEMPOTENCY_CONFLICT")
    else:
        assert success(second)["data"]["id"] == path.rsplit("/", 1)[1]
        assert second.headers["Idempotent-Replay"] == "true"
    with Session(app.state.engine) as session:
        row = session.exec(select(CitizenReport)).one()
        jobs = session.exec(select(MediaCleanupJob)).all()
        keys = {k for k, _ in storage.list_objects()}
        assert keys == {row.photo_object_key} | {job.object_key for job in jobs}
        assert len(jobs) == int(fail_delete)
        for job in jobs:
            assert job.status == "pending" and job.object_key != row.photo_object_key
        assert storage.get_bytes(row.photo_object_key)
    assert not app.state.in_flight_uploads


@pytest.mark.parametrize("committed,lookup_fails", [(True, False), (False, False), (False, True)])
def test_uncertain_commit_preserves_referenced_or_unknown_photo(
    app, client, account, monkeypatch, committed, lookup_fails,
):
    values = fields()
    commit = Session.commit
    lookup = repository.by_request
    attempted = False

    def uncertain(session):
        nonlocal attempted
        if any(isinstance(row, CitizenReport) for row in session.new):
            attempted = True
            if committed:
                commit(session)
            else:
                session.flush()
            raise SQLAlchemyError("Commit acknowledgement unavailable")
        return commit(session)

    def maybe_unavailable(*args):
        if attempted and lookup_fails:
            raise SQLAlchemyError("Connection unavailable")
        return lookup(*args)

    with monkeypatch.context() as patch:
        patch.setattr(Session, "commit", uncertain)
        patch.setattr(repository, "by_request", maybe_unavailable)
        response = submit(client, account[2], values, jpeg())
    assert attempted
    objects = app.state.storage.list_objects()
    assert not app.state.in_flight_uploads
    with Session(app.state.engine) as session:
        rows = session.exec(select(CitizenReport)).all()
        if committed:
            data = success(response)["data"]
            assert response.headers["Idempotent-Replay"] == "true"
            assert len(rows) == len(objects) == 1
            assert rows[0].photo_object_key == objects[0][0] and str(rows[0].id) == data["id"]
        else:
            error(response, 503, "SERVICE_UNAVAILABLE")
            assert not rows
            assert len(objects) == int(lookup_fails)
    retry = submit(client, account[2], values, jpeg())
    success(retry, 200 if committed else 201)


def test_failed_audit_rolls_back_claim(client, app, account, actor):
    path = created(submit(client, account[2], fields()))
    admin = actor("admin")

    def reject_audit(conn, cursor, statement, parameters, context, executemany):
        if statement.startswith("INSERT INTO siaga.report_verifications"):
            raise SQLAlchemyError("Audit unavailable")

    event.listen(app.state.engine, "before_cursor_execute", reject_audit)
    try:
        error(claim(client, admin, path), 503, "SERVICE_UNAVAILABLE")
    finally:
        event.remove(app.state.engine, "before_cursor_execute", reject_audit)
    with Session(app.state.engine) as session:
        row = session.get(CitizenReport, UUID(path.rsplit("/", 1)[1]))
        assert row.version == 1 and row.status == "pending" and row.reviewer_id is None
        assert not session.exec(select(ReportVerification)).all()
    success(claim(client, admin, path))
