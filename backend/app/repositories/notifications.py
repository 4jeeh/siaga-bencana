from sqlalchemy import func, update
from sqlmodel import select

from app.core.errors import ApiError
from app.models.disaster_event import DisasterEvent
from app.models.notification_log import NotificationLog
from app.models.user import User
from app.schemas.notifications import MAX_SEQUENCE


def _notifications(user_id):
    return (
        select(NotificationLog, DisasterEvent)
        .join(DisasterEvent, NotificationLog.event_id == DisasterEvent.id)
        .where(NotificationLog.user_id == user_id)
    )


def history_rows(session, user_id, query):
    if query.offset > MAX_SEQUENCE:
        return []
    statement = _notifications(user_id)
    if query.unread_only:
        statement = statement.where(NotificationLog.read_at.is_(None))
    return session.exec(
        statement.order_by(NotificationLog.sequence.desc(), NotificationLog.id.desc())
        .offset(query.offset)
        .limit(query.limit + 1)
    ).all()


def unread_count(session, user_id):
    return session.exec(select(func.count()).select_from(NotificationLog).where(
        NotificationLog.user_id == user_id, NotificationLog.read_at.is_(None)
    )).one()


def set_first_read(session, user_id, notification_id, now):
    table = NotificationLog.__table__
    statement = (
        update(table)
        .where(table.c.id == notification_id, table.c.user_id == user_id)
        .values(read_at=func.coalesce(table.c.read_at, now))
        .returning(table.c.id, table.c.read_at)
    )
    return session.execute(statement).mappings().one_or_none()


def high_water_mark(session, user_id):
    hwm = session.exec(select(User.last_notification_sequence).where(
        User.id == user_id, User.active.is_(True)
    )).one_or_none()
    if hwm is None:
        raise ApiError(401, "TOKEN_INVALID", "Sesi tidak valid, masuk kembali.")
    return hwm


def retained_count(session, user_id, hwm):
    # The unique (user_id, sequence) index makes this an exact check of 1..hwm.
    return session.exec(select(func.count()).select_from(NotificationLog).where(
        NotificationLog.user_id == user_id, NotificationLog.sequence.between(1, hwm)
    )).one()


def catch_up_rows(session, user_id, since, hwm, limit):
    return session.exec(
        _notifications(user_id)
        .where(NotificationLog.sequence > since, NotificationLog.sequence <= hwm)
        .order_by(NotificationLog.sequence.asc())
        .limit(limit)
    ).all()
