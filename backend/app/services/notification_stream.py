import asyncio
import json
import logging
from contextlib import contextmanager
from datetime import UTC, datetime
from threading import Lock
from uuid import UUID

from sqlalchemy.exc import DBAPIError
from sqlalchemy.exc import TimeoutError as PoolTimeout
from sqlmodel import Session

from app.core.errors import ApiError
from app.repositories import notifications as repo
from app.services.notifications import notification_gap, read_batch

logger = logging.getLogger("siaga.notifications.stream")


class StreamRegistry:
    def __init__(self):
        self._lock = Lock()
        self._owners: dict[UUID, object] = {}

    @contextmanager
    def reserve(self, user_id):
        token = object()
        with self._lock:
            if user_id in self._owners:
                raise ApiError(
                    429, "STREAM_LIMIT_REACHED", "Kanal notifikasi akun ini sudah aktif.",
                    headers={"Retry-After": "3"},
                )
            self._owners[user_id] = token
        try:
            yield
        finally:
            with self._lock:
                if self._owners.get(user_id) is token:
                    del self._owners[user_id]


def snapshot(state, user_id, since, *, initial=False):
    limit = min(50, max(1, state.stream_batch_size))
    try:
        with state.engine.connect().execution_options(
            isolation_level="REPEATABLE READ", postgresql_readonly=True
        ) as conn, Session(bind=conn) as session:
            hwm = repo.high_water_mark(session, user_id)
            items = read_batch(session, user_id, since, hwm, limit, state.settings.domain_now())
            if initial and repo.retained_count(session, user_id, hwm) != hwm:
                raise notification_gap(user_id, since, hwm)
            return hwm, items
    except (DBAPIError, PoolTimeout) as exc:
        raise ApiError(503, "SERVICE_UNAVAILABLE", "Layanan notifikasi belum siap.") from exc


async def frames(state, user_id, since, expires, first_batch):
    loop = asyncio.get_running_loop()
    heartbeat = state.stream_heartbeat_seconds
    next_heartbeat = loop.time() + heartbeat

    def remaining():
        return (expires - datetime.now(UTC)).total_seconds()

    hwm, items = first_batch
    connected = {
        "cursor_user_id": str(user_id), "since_sequence": since, "high_water_mark": hwm,
        "heartbeat_seconds": heartbeat, "is_simulated": state.settings.app_mode == "simulation",
    }
    try:
        if state.stop.is_set() or remaining() <= 0:
            return
        yield f"retry: 3000\nevent: connected\ndata: {json.dumps(connected)}\n\n"
        while not state.stop.is_set() and remaining() > 0:
            for item in items:
                if state.stop.is_set() or remaining() <= 0:
                    return
                since = item.sequence
                yield f"id: {user_id}:{since}\nevent: alert\ndata: {item.model_dump_json()}\n\n"

            # Drain an existing backlog, then poll at the idle interval.
            next_poll = loop.time() + (0 if since < hwm else state.stream_poll_seconds)
            while not state.stop.is_set() and remaining() > 0:
                now = loop.time()
                if now >= next_heartbeat:
                    stamp = state.settings.domain_now().isoformat().replace("+00:00", "Z")
                    payload = json.dumps({"server_time": stamp})
                    next_heartbeat = now + heartbeat
                    yield f": keepalive\nevent: heartbeat\ndata: {payload}\n\n"
                    if state.stop.is_set() or remaining() <= 0:
                        return
                    now = loop.time()
                if now >= next_poll:
                    hwm, items = await asyncio.to_thread(snapshot, state, user_id, since)
                    break
                delay = min(next_poll - now, next_heartbeat - now, remaining())
                try:
                    await asyncio.wait_for(state.stop.wait(), timeout=delay)
                except TimeoutError:
                    pass
    except Exception as exc:
        # Headers have been sent. End the body without exposing SQL or a JSON error frame.
        logger.warning("stream_closed user_id=%s exception_type=%s", user_id, type(exc).__name__)
