"""Fenced source leases and atomic BMKG cache/notification/checkpoint commits."""

import asyncio
import logging
import time
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, text, update
from sqlalchemy.exc import SQLAlchemyError
from sqlmodel import Session, select

from app.models.disaster_event import DisasterEvent
from app.models.sync_run import SyncRun
from app.services.bmkg_batch import Batch, collect
from app.services.bmkg_events import notify, save_event, settle_lifecycle
from app.services.bmkg_fetch import check_time, open_fetcher
from app.services.bmkg_parser import NOWCAST, TEWS

LOCK_KEYS = {TEWS: 0x424D01, NOWCAST: 0x424D02}
logger = logging.getLogger("siaga.bmkg")


def latest(source):
    return (
        select(SyncRun)
        .where(SyncRun.source == source)
        .order_by(SyncRun.started_at.desc(), SyncRun.id.desc())
        .limit(1)
    )


def claim_lease(engine, source):
    with Session(engine, expire_on_commit=False) as session, session.begin():
        locked = session.execute(
            text("SELECT pg_try_advisory_xact_lock(:key)"), {"key": LOCK_KEYS[source]}
        ).scalar_one()
        if not locked:
            return None
        now = datetime.now(UTC)
        session.execute(
            update(SyncRun)
            .where(
                SyncRun.source == source,
                SyncRun.status == "running",
                SyncRun.lease_until <= now,
            )
            .values(status="abandoned", finished_at=now, error_code="LEASE_EXPIRED")
        )
        if (
            session.exec(
                select(SyncRun.id).where(SyncRun.source == source, SyncRun.status == "running")
            ).first()
            is not None
        ):
            return None
        prior = session.exec(latest(source)).first()
        run = SyncRun(
            source=source,
            status="running",
            started_at=now,
            lease_until=now + timedelta(seconds=300),
            last_success_at=prior.last_success_at if prior else None,
            bootstrap_completed=prior.bootstrap_completed if prior else False,
            checkpoint=prior.checkpoint if prior else {},
        )
        session.add(run)
    return run


class LostLease(Exception):
    pass


def write_batch(engine, lease, batch, settings, deadline=None):
    with Session(engine) as session, session.begin():
        run = session.exec(
            select(SyncRun)
            .where(
                SyncRun.id == lease.id,
                SyncRun.lease_token == lease.lease_token,
                SyncRun.status == "running",
                SyncRun.lease_until > func.clock_timestamp(),
            )
            .with_for_update()
        ).one_or_none()
        if run is None or run.lease_until <= datetime.now(UTC):
            raise LostLease
        now = settings.domain_now()
        new_events = []
        pending = []
        for record in batch.records.values():
            if deadline is not None:
                check_time(deadline)
            event, new, changed = save_event(
                session, record, now, settings.app_mode == "simulation"
            )
            run.changed_count += int(changed)
            run.valid_count += 1
            pending.append((event, record))
            if new:
                new_events.append((event, record))
        settle_lifecycle(session, pending, now)
        if run.bootstrap_completed:
            notify(session, new_events, now)
        session.flush()
        if deadline is not None:
            check_time(deadline)
        finished = datetime.now(UTC)
        if run.lease_until <= finished:
            raise LostLease
        run.finished_at = finished
        run.checkpoint = batch.checkpoint
        run.invalid_count = batch.invalid
        run.status = batch.status
        if run.status == "success":
            run.last_success_at = finished
            run.bootstrap_completed = True
        else:
            run.error_code = batch.error or "INVALID_DOCUMENT"
            run.error_summary = "Sebagian data BMKG belum dapat disinkronkan."
    return batch.status


def sync_source(engine, settings, source, fetcher):
    lease = claim_lease(engine, source)
    if lease is None:
        return None
    deadline = time.monotonic() + 240
    try:
        batch = collect(source, lease.checkpoint, fetcher, deadline)
        return write_batch(engine, lease, batch, settings, deadline)
    except LostLease:
        return None
    except Exception as exc:
        # The failed write rolled back; close only our own still-valid lease.
        logger.warning("BMKG source=%s failure=%s", source, type(exc).__name__)
        try:
            return write_batch(
                engine, lease, Batch(checkpoint=lease.checkpoint, error="BATCH_FAILED"), settings
            )
        except LostLease:
            return None


def source_freshness(session, now):
    sources = []
    for source in LOCK_KEYS:
        run = session.exec(latest(source)).first()
        success = run.last_success_at if run else None
        outcome = run
        if run and run.status == "running":
            outcome = session.exec(latest(source).where(SyncRun.status != "running")).first()
        if not success:
            cached = session.exec(
                select(DisasterEvent.id).where(DisasterEvent.source == source).limit(1)
            ).first()
            state = "degraded" if cached else "unavailable"
        elif now - success > timedelta(minutes=15):
            state = "stale"
        elif outcome and outcome.status == "success":
            state = "healthy"
        else:
            state = "degraded"
        sources.append(
            dict(
                source=source,
                state=state,
                last_success_at=success,
                last_attempt_at=run.started_at if run else None,
            )
        )
    return sources


async def scheduler(engine, settings, stop):
    def attempt(source):
        try:
            with open_fetcher() as fetcher:
                sync_source(engine, settings, source, fetcher)
        except SQLAlchemyError as exc:
            logger.warning("BMKG source=%s database=%s", source, type(exc).__name__)

    while not stop.is_set():
        await asyncio.gather(*(asyncio.to_thread(attempt, source) for source in LOCK_KEYS))
        try:
            await asyncio.wait_for(stop.wait(), timeout=max(1, settings.sync_interval_seconds))
        except TimeoutError:
            pass
