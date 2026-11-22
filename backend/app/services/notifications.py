import logging
from datetime import datetime

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session

from app.core.errors import ApiError
from app.models.disaster_event import DisasterEvent
from app.models.notification_log import NotificationLog
from app.repositories import notifications as repo
from app.schemas.events import Page
from app.schemas.notifications import (
    NotificationDTO,
    NotificationHistoryFeed,
    NotificationReadData,
    NotificationSyncFeed,
)
from app.services import radar
from app.services.bmkg_parser import TEWS

logger = logging.getLogger("siaga.notifications")


def build_notification_dto(log: NotificationLog, event: DisasterEvent, now: datetime):
    if event.source == TEWS:
        status = radar.earthquake_lifecycle_status(event.occurred_at, now)
        active = status == "current"
    else:
        status = radar.cap_lifecycle_status(
            msg_type=event.msg_type,
            sent=event.sent,
            cancelled=event.cancelled_at is not None,
            superseded=event.superseded_at is not None,
            lifecycle_complete=event.lifecycle_complete,
            effective=event.effective or event.sent,
            expires=event.expires,
            evaluated_at=now,
        )
        active = event.status == "Actual" and status == "active"
    return NotificationDTO(
        **log.model_dump(exclude={"user_id"}),
        title=event.title,
        event_category=event.category,
        current_lifecycle_status=status,
        present_as_active_alert=active,
    )


def history(session, user, query, meta):
    rows = repo.history_rows(session, user.id, query)
    has_more = len(rows) > query.limit
    return NotificationHistoryFeed(
        items=[
            build_notification_dto(log, event, meta["server_time"])
            for log, event in rows[:query.limit]
        ],
        page=Page(
            limit=query.limit, offset=query.offset, has_more=has_more,
            next_offset=query.offset + query.limit if has_more else None,
        ),
        unread_count=repo.unread_count(session, user.id),
        meta=meta,
    )


def mark_read(session, user, notification_id, settings):
    try:
        row = repo.set_first_read(session, user.id, notification_id, settings.domain_now())
        if row is None:
            raise ApiError(404, "RESOURCE_NOT_FOUND", "Notifikasi tidak ditemukan.")
        data = NotificationReadData.model_validate(row)
        session.commit()
        return data
    except IntegrityError:
        session.rollback()
        raise ApiError(503, "SERVICE_UNAVAILABLE", "Waktu baca tidak dapat disimpan.") from None


def sync(engine, user_id, query, settings, meta):
    cursor = query.catch_up()
    if cursor is not None and cursor[0] != user_id:
        raise ApiError(
            409, "CURSOR_USER_MISMATCH", "Cursor notifikasi tidak sesuai dengan akun aktif.",
            {"action": "fetch_baseline"},
        )
    with engine.connect().execution_options(
        isolation_level="REPEATABLE READ", postgresql_readonly=True
    ) as conn, Session(bind=conn) as session:
        hwm = repo.high_water_mark(session, user_id)
        items = []
        next_sequence = hwm
        if cursor is not None:
            _, since, limit = cursor
            if since > hwm:
                raise ApiError(
                    409, "CURSOR_OUT_OF_RANGE", "Cursor notifikasi melebihi batas terbaru.",
                    {"action": "fetch_baseline"},
                )
            rows = repo.catch_up_rows(session, user_id, since, hwm, limit)
            expected = min(limit, hwm - since)
            if len(rows) != expected or [log.sequence for log, _ in rows] != list(
                range(since + 1, since + expected + 1)
            ):
                logger.error("notification_gap user_id=%s since=%s hwm=%s", user_id, since, hwm)
                raise ApiError(
                    503, "SERVICE_UNAVAILABLE",
                    "Integritas urutan notifikasi terganggu. Coba lagi nanti.",
                )
            now = settings.domain_now()
            items = [build_notification_dto(log, event, now) for log, event in rows]
            next_sequence = rows[-1][0].sequence if rows else since
    return NotificationSyncFeed(
        items=items, cursor_user_id=user_id, high_water_mark=hwm, next_sequence=next_sequence,
        has_more=next_sequence < hwm, meta=meta,
    )
