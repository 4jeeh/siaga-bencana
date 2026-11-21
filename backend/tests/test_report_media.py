import hashlib
import json
import os
import struct
from datetime import UTC, datetime, timedelta
from io import BytesIO
from unittest.mock import Mock
from urllib.parse import parse_qs, urlsplit
from uuid import UUID, uuid4

import httpx
import pytest
from PIL import Image
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import ApiError
from app.models.citizen_report import CitizenReport, MediaCleanupJob
from app.models.user import User
from app.services import media
from app.services.media_cleanup import (
    enqueue_cleanup,
    process_cleanup_jobs,
    reconcile_orphan_objects,
)
from app.services.report_payload import canonicalize_report_payload
from app.services.storage import (
    LocalStorageAdapter,
    SupabaseStorageAdapter,
    build_storage_adapter,
    generate_object_key,
    verify_local_photo_signature,
)
from tests.conftest import isolated_database

NOW = datetime(2026, 11, 22, 12, tzinfo=UTC)


def jpeg(size=(32, 16), **kwargs):
    buffer = BytesIO()
    Image.new("RGB", size, "red").save(buffer, format="JPEG", **kwargs)
    return buffer.getvalue()


@pytest.mark.parametrize("size, expected", [((60, 20), (20, 60)), ((1500, 750), (512, 1024))])
def test_sanitize_orients_strips_metadata_and_is_deterministic(size, expected):
    exif = Image.Exif()
    exif[274] = 6
    exif[34853] = {1: "N", 2: (1, 2, 3)}
    raw = jpeg(size, exif=exif, comment=b"private note", icc_profile=b"private profile")
    with Image.open(BytesIO(raw)) as original:
        assert original.getexif().get_ifd(34853)[1] == "N"
        assert original.info["icc_profile"] and original.info["comment"]

    photo = media.sanitize_jpeg(raw, " Image/JPEG ; charset=binary")
    assert photo == media.sanitize_jpeg(raw, "image/jpeg")
    assert photo.sha256 == hashlib.sha256(photo.data).hexdigest()
    assert photo.size_bytes == len(photo.data)
    with Image.open(BytesIO(photo.data)) as image:
        assert image.size == (photo.width, photo.height) == expected
        assert image.mode == "RGB" and image.format == "JPEG"
        assert not image.getexif()
        assert not {"exif", "icc_profile", "comment"} & image.info.keys()


@pytest.mark.parametrize(
    "raw,mime,status",
    [
        (b"", "image/jpeg", 422),
        (b"x" * (media.MAX_PHOTO_BYTES + 1), "image/jpeg", 413),
        (b"\x89PNG\r\n\x1a\n", "image/jpeg", 415),
        (jpeg(), "image/png", 415),
        (b"fake", "image/jpeg", 415),
        (b"\xff\xd8\xffinvalid", "image/jpeg", 422),
        (jpeg()[:-10], "image/jpeg", 422),
    ],
)
def test_invalid_image(raw, mime, status):
    with pytest.raises(ApiError) as error:
        media.sanitize_jpeg(raw, mime)
    assert error.value.status == status
    if status == 413:
        assert error.value.details == {"max_bytes": media.MAX_PHOTO_BYTES}


@pytest.mark.parametrize("width,height", [(4097, 1), (4001, 4000), (65535, 65535)])
def test_rejects_oversized_headers_before_decode(width, height):
    raw = bytearray(jpeg())
    start = raw.index(b"\xff\xc0") + 5
    raw[start : start + 4] = struct.pack(">HH", height, width)
    with pytest.raises(ApiError) as error:
        media.sanitize_jpeg(bytes(raw), "image/jpeg")
    assert error.value.status == 422


@pytest.mark.parametrize("mode", ["RGBA", "LA"])
def test_rejects_alpha_before_conversion(monkeypatch, mode):
    # Legal JPEGs cannot carry alpha. Exercise the decoder boundary directly.
    raw = jpeg()
    image = Image.new(mode, (2, 2))
    image.format = "JPEG"
    monkeypatch.setattr(Image, "open", lambda _: image)
    with pytest.raises(ApiError) as error:
        media.sanitize_jpeg(raw, "image/jpeg")
    assert error.value.status == 422


def payload(**changes):
    fields = dict(
        category="flood",
        description=" \tBanjir dekat cafe\u0301 di jalan utama.\u2002",
        client_request_id=str(uuid4()),
        latitude="-0.0000004",
        longitude="+180",
    )
    return canonicalize_report_payload(**(fields | changes))


def test_payload_matches_canonical_utf8_vector():
    expected = (
        '{"algo":"report-payload-v1","category":"flood",'
        '"description":"Banjir dekat café di jalan utama.","event_id":null,'
        '"latitude":"0.000000","longitude":"-180.000000","photo_sha256":null}'
    )
    first = payload()
    second = payload(longitude="179.9999999", latitude="0")
    assert first.client_request_id != second.client_request_id
    assert (
        first.payload_hash == second.payload_hash == hashlib.sha256(expected.encode()).hexdigest()
    )
    assert (first.latitude, first.longitude) == (0, -180)
    assert (first.lat_fixed6, first.lon_fixed6) == ("0.000000", "-180.000000")
    uid = str(uuid4()).upper()
    event = payload(event_id=uid, client_request_id=uid, latitude="-7.2500005")
    assert event.event_id == event.client_request_id == UUID(uid)
    assert event.lat_fixed6 == "-7.250001"
    assert first.payload_hash != payload(photo_sha256="b" * 64).payload_hash


@pytest.mark.parametrize(
    "field,value",
    [
        ("event_id", "null"),
        ("event_id", ""),
        ("event_id", "123"),
        ("client_request_id", ""),
        ("category", "other"),
        ("description", "x" * 19),
        ("description", "x" * 1001),
        ("latitude", "NaN"),
        ("latitude", "Infinity"),
        ("latitude", "-90.0000001"),
        ("longitude", "180.0000001"),
        ("longitude", ""),
        ("longitude", "abc"),
    ],
)
def test_invalid_payload(field, value):
    with pytest.raises(ApiError) as error:
        payload(**{field: value})
    assert (error.value.status, error.value.code) == (422, "VALIDATION_ERROR")


@pytest.fixture
def config(tmp_path):
    return Settings(
        _env_file=None,
        database_url="postgresql+psycopg://siaga_runtime@localhost/db",
        jwt_secret="j" * 32,
        media_signing_secret="m" * 32,
        storage_root=tmp_path / "private",
        storage_bucket="reports",
        supabase_url="https://storage.test",
        supabase_service_key="test-key",
    )


def test_local_signature(config):
    report, key = uuid4(), generate_object_key()
    adapter = build_storage_adapter(config)
    url, expiry, ttl = adapter.create_signed_url("https://api.test/", report, key, now=NOW)
    parts = urlsplit(url)
    assert parts.path == f"/api/v1/media/reports/{report}/photo"
    query = parse_qs(parts.query)
    expires = int(query["expires"][0])
    sig = query["signature"][0]
    assert "=" not in sig and ttl == 300 and expiry.timestamp() == expires

    def verify(r=report, k=key, e=expires, s=sig, now=NOW):
        return verify_local_photo_signature(r, k, e, s, config, now=now)

    assert verify()
    assert not verify(r=uuid4()) and not verify(k=generate_object_key())
    assert not verify(e=expires - 1) and not verify(s="invalid") and not verify(now=expiry)
    assert not verify(now=NOW - timedelta(seconds=1))
    config.app_mode = "simulation"
    assert not verify()
    config.app_mode = "local_live"
    config.storage_backend = "supabase"
    assert not verify()


def test_local_storage_atomic_and_private(config, monkeypatch):
    adapter = LocalStorageAdapter(config)
    key = generate_object_key()
    adapter.put_bytes(key, b"original")
    with monkeypatch.context() as patch:
        patch.setattr(os, "replace", Mock(side_effect=OSError("internal path")))
        with pytest.raises(ApiError) as error:
            adapter.put_bytes(key, b"incomplete")
    assert error.value.status == 503 and adapter.get_bytes(key) == b"original"
    assert [p.name for p in config.storage_root.iterdir()] == [key]
    adapter.put_bytes(key, b"replacement")
    assert adapter.get_bytes(key) == b"replacement"
    [(listed, modified)] = adapter.list_objects()
    assert listed == key and modified.tzinfo == UTC
    for operation in [
        adapter.get_bytes,
        adapter.delete_object,
        lambda k: adapter.put_bytes(k, b"x"),
    ]:
        with pytest.raises(ApiError):
            operation("../" + key)
    adapter.delete_object(key)
    adapter.delete_object(key)
    with pytest.raises(FileNotFoundError):
        adapter.get_bytes(key)


@pytest.mark.parametrize("absolute", [False, True])
def test_supabase_storage(config, absolute):
    key = generate_object_key()
    relative = f"/object/sign/reports/{key}?token=abc"
    full = "https://storage.test/storage/v1" + relative

    def handle(req):
        assert req.headers["apikey"] == "test-key"
        assert req.headers["authorization"] == "Bearer test-key"
        path = req.url.path.removeprefix("/storage/v1")
        if req.method == "GET" and path == "/bucket/reports":
            return httpx.Response(200, json={"public": False})
        if req.method == "POST" and path == f"/object/reports/{key}":
            assert req.content == b"photo" and req.headers["content-type"] == "image/jpeg"
            assert req.headers["x-upsert"] == "false"
            return httpx.Response(201)
        if req.method == "POST" and path == f"/object/sign/reports/{key}":
            assert json.loads(req.content) == {"expiresIn": 120}
            return httpx.Response(200, json={"signedURL": full if absolute else relative})
        if req.method == "POST" and path == "/object/list/reports":
            return httpx.Response(200, json=[{"name": key, "created_at": NOW.isoformat()}])
        assert req.method == "DELETE" and path == f"/object/reports/{key}"
        return httpx.Response(404)

    adapter = SupabaseStorageAdapter(config, httpx.MockTransport(handle))
    assert adapter.check_ready()
    adapter.put_bytes(key, b"photo")
    assert adapter.create_signed_url("", uuid4(), key, now=NOW, ttl_seconds=120) == (
        full,
        NOW + timedelta(seconds=120),
        120,
    )
    assert adapter.list_objects() == [(key, NOW)]
    adapter.delete_object(key)


@pytest.mark.parametrize(
    "status,body", [(200, {"public": True}), (200, {}), (404, {"public": False})]
)
def test_supabase_readiness_requires_private_bucket(config, status, body):
    transport = httpx.MockTransport(lambda req: httpx.Response(status, json=body))
    assert not SupabaseStorageAdapter(config, transport).check_ready()
    config.supabase_url = "file:///tmp/"
    adapter = SupabaseStorageAdapter(config, transport)
    assert not adapter.is_configured and not adapter.check_ready()


def test_supabase_failure_is_redacted(config):
    def fail(request):
        raise httpx.ConnectError("internal url")

    adapter = SupabaseStorageAdapter(config, httpx.MockTransport(fail))
    assert not adapter.check_ready()
    with pytest.raises(ApiError) as error:
        adapter.put_bytes(generate_object_key(), b"photo")
    assert error.value.status == 503 and "internal" not in error.value.message


@pytest.fixture
def db_engine():
    with isolated_database() as db:
        engine = create_engine(db["runtime"].replace("postgresql:", "postgresql+psycopg:"))
        try:
            yield engine
        finally:
            engine.dispose()


def test_cleanup_protects_references_and_inflight_then_reconciles(db_engine, config):
    adapter = LocalStorageAdapter(config)
    old = NOW - timedelta(days=1, seconds=1)
    referenced, active, orphan, recent = (generate_object_key() for _ in range(4))
    for key in (referenced, active, orphan, recent):
        adapter.put_bytes(key, b"x")
        stamp = NOW - timedelta(days=1) if key == recent else old
        os.utime(config.storage_root / key, (stamp.timestamp(), stamp.timestamp()))
    with Session(db_engine) as db, db.begin():
        user = User(
            email="demo@example.test",
            display_name="Demo",
            password_hash="$argon2-fixture",
            created_at=NOW,
            updated_at=NOW,
        )
        db.add(user)
        db.flush()
        db.add(
            CitizenReport(
                reporter_id=user.id,
                client_request_id=uuid4(),
                payload_hash="a" * 64,
                category="flood",
                description="Permukaan sungai mulai naik.",
                latitude=0,
                longitude=0,
                photo_storage_backend="local",
                photo_object_key=referenced,
                photo_sha256="b" * 64,
                photo_bytes=1,
                photo_width=1,
                photo_height=1,
            )
        )
        db.flush()
        args = dict(storage_backend="local", now=NOW, active_keys=[active])
        assert reconcile_orphan_objects(db, Mock(spec=[]), db_healthy=False, **args) == []
        assert reconcile_orphan_objects(db, adapter, db_healthy=True, **args) == [orphan]
        assert reconcile_orphan_objects(db, adapter, db_healthy=True, **args) == []
        for key in (referenced, active):
            enqueue_cleanup(
                db, storage_backend="local", object_key=key, object_created_at=old, now=NOW
            )
        assert process_cleanup_jobs(db, adapter, **args) == 3
        states = dict(db.execute(select(MediaCleanupJob.object_key, MediaCleanupJob.status)).all())
        assert states == {referenced: "cancelled", active: "cancelled", orphan: "done"}
        assert {key for key, _ in adapter.list_objects()} == {referenced, active, recent}
        assert reconcile_orphan_objects(
            db, adapter, db_healthy=True, storage_backend="local", now=NOW
        ) == [active]
        assert process_cleanup_jobs(db, adapter, storage_backend="local", now=NOW) == 1
        assert {key for key, _ in adapter.list_objects()} == {referenced, recent}


def test_cleanup_skips_locked_and_retries(db_engine):
    key = generate_object_key()
    adapter = Mock()
    args = dict(storage_backend="local", now=NOW)
    with Session(db_engine) as db, db.begin():
        enqueue_cleanup(db, object_key=key, object_created_at=NOW, **args)
    with Session(db_engine) as locker, locker.begin(), Session(db_engine) as db, db.begin():
        locker.scalar(select(MediaCleanupJob).with_for_update())
        assert process_cleanup_jobs(db, adapter, **args) == 0
        adapter.delete_object.assert_not_called()
    with Session(db_engine) as db, db.begin():
        adapter.delete_object.side_effect = OSError("private")
        assert process_cleanup_jobs(db, adapter, **args) == 1
        job = db.scalars(select(MediaCleanupJob)).one()
        assert job.status == "pending" and job.attempts == 1 and "private" not in job.last_error
        retry_at = job.next_attempt_at
        assert retry_at > NOW and process_cleanup_jobs(db, adapter, **args) == 0
        adapter.delete_object.side_effect = None
        assert process_cleanup_jobs(db, adapter, storage_backend="local", now=retry_at) == 1
        assert job.status == "done" and job.last_error is None
