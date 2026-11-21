from collections.abc import Iterable
from datetime import datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core.errors import ApiError
from app.models.citizen_report import CitizenReport, MediaCleanupJob
from app.services.storage import LocalStorageAdapter, SupabaseStorageAdapter, validate_object_key

type Adapter = LocalStorageAdapter | SupabaseStorageAdapter


def enqueue_cleanup(
    session: Session,
    *,
    storage_backend: str,
    object_key: str,
    object_created_at: datetime,
    now: datetime,
    last_error: str | None = None,
):
    """Queue once in the caller's transaction. Persist no upstream error text."""
    validate_object_key(object_key)
    statement = (
        insert(MediaCleanupJob)
        .values(
            storage_backend=storage_backend,
            object_key=object_key,
            object_created_at=object_created_at,
            next_attempt_at=now,
            created_at=now,
            updated_at=now,
            last_error="Penyimpanan foto belum tersedia." if last_error else None,
        )
        .on_conflict_do_nothing(index_elements=[MediaCleanupJob.object_key])
    )
    return session.scalar(statement.returning(MediaCleanupJob.id)) is not None


def _referenced(session: Session, key: str) -> bool:
    return (
        session.scalar(select(CitizenReport.id).where(CitizenReport.photo_object_key == key))
        is not None
    )


def process_cleanup_jobs(
    session: Session,
    adapter: Adapter,
    *,
    storage_backend: str,
    now: datetime,
    active_keys: Iterable[str] = (),
    limit: int = 20,
) -> int:
    """Process due rows under row locks until the caller commits or rolls back."""
    if limit <= 0:
        return 0
    jobs = session.scalars(
        select(MediaCleanupJob)
        .where(
            MediaCleanupJob.status == "pending",
            MediaCleanupJob.next_attempt_at <= now,
            MediaCleanupJob.storage_backend == storage_backend,
        )
        .order_by(MediaCleanupJob.next_attempt_at, MediaCleanupJob.id)
        .limit(limit)
        .with_for_update(skip_locked=True)
    ).all()
    active = set(active_keys)
    for job in jobs:
        job.updated_at = now
        job.last_error = None
        if job.object_key in active or _referenced(session, job.object_key):
            job.status = "cancelled"
            continue
        try:
            adapter.delete_object(job.object_key)
        except ApiError, OSError:
            job.attempts += 1
            delay = min(3600, 30 * 2 ** min(job.attempts - 1, 7))
            job.next_attempt_at = now + timedelta(seconds=delay)
            job.last_error = "Penghapusan foto gagal."
        else:
            job.status = "done"
    session.flush()
    return len(jobs)


def reconcile_orphan_objects(
    session: Session,
    adapter: Adapter,
    *,
    storage_backend: str,
    db_healthy: bool,
    now: datetime,
    active_keys: Iterable[str] = (),
) -> list[str]:
    """Queue stale orphans. The worker rechecks references immediately before deletion."""
    if db_healthy is not True:
        return []
    active = set(active_keys)
    cutoff = now - timedelta(hours=24)
    queued = []
    for key, created in adapter.list_objects():
        if created >= cutoff or key in active or _referenced(session, key):
            continue
        scheduled = enqueue_cleanup(
            session,
            storage_backend=storage_backend,
            object_key=key,
            object_created_at=created,
            now=now,
        )
        if not scheduled:
            # An upload protected by the worker may subsequently have been abandoned.
            scheduled = (
                session.scalar(
                    update(MediaCleanupJob)
                    .where(
                        MediaCleanupJob.object_key == key,
                        MediaCleanupJob.storage_backend == storage_backend,
                        MediaCleanupJob.status == "cancelled",
                    )
                    .values(status="pending", next_attempt_at=now, updated_at=now, attempts=0)
                    .returning(MediaCleanupJob.id)
                )
                is not None
            )
        if scheduled:
            queued.append(key)
    return queued
