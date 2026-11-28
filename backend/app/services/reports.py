import unicodedata
from datetime import UTC, datetime

from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlmodel import Session, select

from app.core.errors import ApiError
from app.models.citizen_report import CitizenReport, ReportVerification
from app.models.disaster_event import DisasterEvent
from app.models.user import User
from app.repositories import reports as repo
from app.repositories.zones import by_user
from app.schemas.reports import (
    DecisionRequest,
    ModerationResult,
    PhotoUrlData,
    ReportPrivate,
    ReportPublic,
    VerificationDTO,
)
from app.services.events import invalid_query
from app.services.media import sanitize_jpeg
from app.services.media_cleanup import enqueue_cleanup
from app.services.radar import haversine_km
from app.services.report_payload import canonicalize_report_payload
from app.services.storage import generate_object_key, verify_local_photo_signature


def not_found():
    return ApiError(404, "RESOURCE_NOT_FOUND", "Laporan tidak ditemukan.")


def photo_missing():
    return ApiError(404, "PHOTO_NOT_FOUND", "Foto tidak ditemukan.")


def unavailable():
    return ApiError(503, "SERVICE_UNAVAILABLE", "Layanan belum tersedia. Coba lagi sebentar.")


def private_access(row, user):
    return row.reporter_id == user.id or user.role == "admin"


def visible_report(session, user, report_id):
    row = session.get(CitizenReport, report_id)
    if row is None or (row.status != "verified" and not private_access(row, user)):
        raise not_found()
    return row


def _dto(row, zone, private, reason=None):
    common = dict(
        id=row.id,
        event_id=row.event_id,
        category=row.category,
        description=row.description,
        latitude=row.latitude,
        longitude=row.longitude,
        status=row.status,
        has_photo=row.photo_object_key is not None,
        is_simulated=row.is_simulated,
        verified_at=row.decided_at if row.status == "verified" else None,
        created_at=row.created_at,
        match_distance_km=(
            haversine_km(zone.latitude, zone.longitude, row.latitude, row.longitude)
            if zone is not None else None
        ),
    )
    if private:
        return ReportPrivate(
            **common,
            reporter_id=row.reporter_id,
            reviewer_id=row.reviewer_id,
            version=row.version,
            client_request_id=row.client_request_id,
            payload_hash=row.payload_hash,
            payload_hash_algo=row.payload_hash_algo,
            claimed_at=row.claimed_at,
            decided_at=row.decided_at,
            latest_reason=reason,
            updated_at=row.updated_at,
        )
    return ReportPublic(**common)


def _items(session, rows, zone, user):
    versions = [(r.id, r.version) for r in rows if r.version > 1 and private_access(r, user)]
    reasons = repo.latest_reasons(session, versions)
    return [_dto(r, zone, private_access(r, user), reasons.get(r.id)) for r in rows]


def detail(session, user, report_id):
    row = visible_report(session, user, report_id)
    return _items(session, [row], by_user(session, user.id), user)[0]


def feed(session, user, query, meta):
    if query.scope == "review":
        if user.role != "admin":
            raise ApiError(403, "FORBIDDEN", "Hanya admin dapat meninjau laporan.")
        if query.status not in (None, "pending", "in_review"):
            raise invalid_query("status")
    if query.scope in ("verified", "nearby") and query.status not in (None, "verified"):
        raise invalid_query("status")
    zone = by_user(session, user.id)
    if query.scope == "nearby" and zone is None:
        raise ApiError(
            409, "ZONE_REQUIRED", "Atur zona pantau terlebih dahulu.", {"action": "setup_zone"}
        )
    rows, page = repo.report_page(session, user.id, zone, query)
    return {
        "items": _items(session, rows, zone, user),
        "page": page,
        "meta": {**meta, "zone_version": zone.zone_version if zone else None},
    }


def _replay(session, user, row, payload):
    if row.payload_hash != payload.payload_hash:
        raise ApiError(
            409, "IDEMPOTENCY_CONFLICT", "Kunci permintaan sudah dipakai untuk laporan berbeda.",
            {"client_request_id": str(payload.client_request_id)},
        )
    return _items(session, [row], by_user(session, user.id), user)[0], True


def _discard_upload(state, key, created_at):
    try:
        with Session(state.engine) as cleanup:
            reference = select(CitizenReport.id).where(CitizenReport.photo_object_key == key)
            if cleanup.exec(reference).first() is not None:
                return
            try:
                state.storage.delete_object(key)
            except (ApiError, OSError):
                enqueue_cleanup(
                    cleanup,
                    storage_backend=state.settings.storage_backend,
                    object_key=key,
                    object_created_at=created_at,
                    now=datetime.now(UTC),
                    last_error="delete",
                )
                cleanup.commit()
    except SQLAlchemyError:
        raise unavailable() from None


def _recover_submit(state, session, user, reporter_id, payload, key, created_at, error):
    # Neither a lost commit acknowledgement nor a failed lookup proves that the
    # upload is unreferenced. Keep the object for reconciliation if SQL is unavailable.
    try:
        session.rollback()
        if not isinstance(error, IntegrityError):
            # A connection can lose COMMIT's reply while PostgreSQL is still committing.
            # The INSERT's reporter FK holds KEY SHARE until that transaction ends.
            # Wait for it before using a fresh READ COMMITTED snapshot to decide on deletion.
            session.exec(select(User.id).where(User.id == reporter_id).with_for_update()).first()
        winner = repo.by_request(session, reporter_id, payload.client_request_id)
        discard = key and (winner is None or winner.photo_object_key != key)
        try:
            if winner is None:
                raise unavailable()
            return _replay(session, user, winner, payload)
        finally:
            if discard:
                # Release the pool connection before enqueueing in a separate transaction.
                session.rollback()
                _discard_upload(state, key, created_at)
    except SQLAlchemyError:
        raise unavailable() from None


def submit(state, session, user, fields, upload):
    photo = sanitize_jpeg(*upload) if upload is not None else None
    payload = canonicalize_report_payload(**fields, photo_sha256=photo.sha256 if photo else None)
    if payload.event_id is not None:
        event = session.get(DisasterEvent, payload.event_id)
        if event is None or (event.category == "extreme_weather" and event.status != "Actual"):
            raise ApiError(404, "RESOURCE_NOT_FOUND", "Informasi bencana tidak ditemukan.")
    reporter_id = user.id
    existing = repo.by_request(session, reporter_id, payload.client_request_id)
    if existing is not None:
        return _replay(session, user, existing, payload)

    settings = state.settings
    now = settings.domain_now()
    key = generate_object_key() if photo else None
    object_created_at = datetime.now(UTC)
    row = CitizenReport(
        reporter_id=reporter_id,
        client_request_id=payload.client_request_id,
        payload_hash=payload.payload_hash,
        category=payload.category,
        description=payload.description,
        latitude=payload.latitude,
        longitude=payload.longitude,
        event_id=payload.event_id,
        status="pending",
        version=1,
        is_simulated=settings.app_mode == "simulation",
        photo_object_key=key,
        photo_storage_backend=settings.storage_backend if photo else None,
        photo_sha256=payload.photo_sha256,
        photo_width=photo.width if photo else None,
        photo_height=photo.height if photo else None,
        photo_bytes=photo.size_bytes if photo else None,
        created_at=now,
        updated_at=now,
    )
    snapshot = _dto(row, by_user(session, reporter_id), True)
    if photo:
        # Release the lookup transaction slot before external object upload.
        session.rollback()
        state.in_flight_uploads.add(key)
    try:
        if photo:
            try:
                state.storage.put_bytes(key, photo.data)
            except (ApiError, OSError):
                session.rollback()
                _discard_upload(state, key, object_created_at)
                raise unavailable() from None
        session.add(row)
        try:
            session.commit()
        except SQLAlchemyError as exc:
            # A unique race and an ambiguous commit both need the winning row and key.
            return _recover_submit(
                state, session, user, reporter_id, payload, key, object_created_at, exc
            )
        return snapshot, False
    finally:
        if key:
            state.in_flight_uploads.discard(key)


def signed_url(request, session, user, report_id):
    row = visible_report(session, user, report_id)
    if row.photo_object_key is None:
        raise photo_missing()
    report_uuid, object_key, is_simulated = row.id, row.photo_object_key, row.is_simulated
    session.close()
    url, expiry, ttl = request.app.state.storage.create_signed_url(
        request.base_url, report_uuid, object_key, ttl_seconds=300
    )
    return PhotoUrlData(url=url, expires_at=expiry, expires_in=ttl, is_simulated=is_simulated)


def local_photo(state, session, report_id, expires, signature):
    row = session.get(CitizenReport, report_id)
    if row is None:
        raise not_found()
    if row.photo_object_key is None:
        raise photo_missing()
    if not verify_local_photo_signature(
        row.id, row.photo_object_key, expires, signature, state.settings
    ):
        raise ApiError(403, "FORBIDDEN", "Tautan foto tidak sah atau sudah kedaluwarsa.")
    try:
        return state.storage.get_bytes(row.photo_object_key)
    except FileNotFoundError:
        raise photo_missing() from None


def moderate(session, user, report_id, body, settings):
    decision = isinstance(body, DecisionRequest)
    reason = "Laporan diambil untuk ditinjau."
    if decision:
        reason = unicodedata.normalize("NFC", body.reason).strip()
        if not 10 <= len(reason) <= 500 or "\x00" in reason:
            raise ApiError(422, "VALIDATION_ERROR", "Alasan keputusan tidak valid.")

    row = repo.locked_report(session, report_id)
    if row is None:
        raise not_found()
    if row.reporter_id == user.id:
        raise ApiError(403, "SELF_REVIEW_FORBIDDEN", "Anda tidak dapat meninjau laporan sendiri.")
    from_status, version = ("in_review", 2) if decision else ("pending", 1)
    if row.status != from_status or row.version != version or row.version != body.expected_version:
        raise ApiError(
            409, "VERSION_CONFLICT", "Laporan telah berubah. Muat ulang sebelum melanjutkan.",
            {"current_version": row.version, "current_status": row.status},
        )
    if decision and row.reviewer_id != user.id:
        raise ApiError(403, "CLAIM_NOT_OWNED", "Laporan sedang ditinjau oleh admin lain.")

    now = settings.domain_now()
    if decision:
        row.status = body.outcome
        row.decided_at = now
    else:
        row.status = "in_review"
        row.reviewer_id = user.id
        row.claimed_at = now
    row.version += 1
    row.updated_at = now
    try:
        session.flush()
        session.add(
            ReportVerification(
                report_id=row.id,
                moderator_id=user.id,
                from_status=from_status,
                to_status=row.status,
                resulting_version=row.version,
                reason=reason,
                created_at=now,
            )
        )
        result = ModerationResult.model_validate(row, from_attributes=True)
        session.commit()
        return result
    except SQLAlchemyError:
        session.rollback()
        raise unavailable() from None


def verifications(session, user, report_id, query, meta):
    row = session.get(CitizenReport, report_id)
    if row is None or not private_access(row, user):
        raise not_found()
    rows, page = repo.verification_page(session, report_id, query)
    items = [VerificationDTO.model_validate(v, from_attributes=True) for v in rows]
    return dict(items=items, page=page, meta=meta)
