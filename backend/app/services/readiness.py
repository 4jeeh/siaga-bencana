import asyncio
import contextlib
import tempfile
import time

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import BACKEND_ROOT
from app.db.migrations import REVISION, TABLES, migration_checksum
from app.services.storage import SupabaseStorageAdapter


class StorageProbe:
    """Private boot probe, refreshed off-request every 30s; stale after 60s."""

    def __init__(self, settings):
        self.settings = settings
        self.ok = False
        self.checked_at = 0.0

    def check(self):
        self.ok = False
        try:
            if self.settings.storage_backend == "supabase":
                self.ok = SupabaseStorageAdapter(self.settings).check_ready()
                return
            path = self.settings.storage_root
            # No symlink/junction traversal, public/static source folder or shared root.
            resolved = path.resolve()
            if (
                resolved != path
                or path == path.parent
                or path in BACKEND_ROOT.parents
                or path == BACKEND_ROOT
                or any(p in {"static", "public", "app", "docs", "mobile"} for p in path.parts)
            ):
                return
            path.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryFile(dir=path) as probe:
                probe.write(b"siaga storage probe")
                probe.flush()
                probe.seek(0)
                self.ok = probe.read() == b"siaga storage probe"
        except OSError:
            self.ok = False
        finally:
            self.checked_at = time.monotonic()

    @property
    def ready(self):
        return self.ok and time.monotonic() - self.checked_at < 60

    async def run(self):
        while True:
            await asyncio.sleep(30)
            await asyncio.to_thread(self.check)


async def start_storage(probe):
    await asyncio.to_thread(probe.check)
    return asyncio.create_task(probe.run())


async def stop_storage(task):
    task.cancel()
    with contextlib.suppress(asyncio.CancelledError):
        await task


def database_ready(engine, runtime_role):
    try:
        with engine.connect() as conn:
            role = conn.execute(
                text("""SELECT current_user, rolsuper, rolcreatedb, rolcreaterole,
                rolreplication, rolbypassrls FROM pg_roles WHERE rolname=current_user""")
            ).one()
            if role[0] != runtime_role or any(role[1:]):
                return False
            schema = conn.execute(
                text("""SELECT pg_has_role(current_user, nspowner, 'MEMBER'),
                has_schema_privilege(current_user, oid, 'CREATE')
                FROM pg_namespace WHERE nspname='siaga'""")
            ).first()
            if not schema or any(schema):
                return False
            tables = conn.execute(
                text("""SELECT c.relname,
                pg_has_role(current_user, c.relowner, 'MEMBER'),
                has_table_privilege(current_user, c.oid, 'SELECT'),
                has_table_privilege(current_user, c.oid, 'DELETE'),
                has_table_privilege(current_user, c.oid, 'TRUNCATE')
                FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                WHERE n.nspname='siaga' AND c.relkind='r'""")
            ).all()
            if {t[0] for t in tables} != TABLES | {"schema_migrations"}:
                return False
            if any(t[1] or not t[2] or t[3] or t[4] for t in tables):
                return False
            unsafe = conn.execute(
                text("""SELECT
                has_any_column_privilege(current_user, 'siaga.report_verifications', 'UPDATE'),
                has_any_column_privilege(current_user, 'siaga.schema_migrations', 'UPDATE'),
                has_table_privilege(current_user, 'siaga.schema_migrations', 'INSERT'),
                has_column_privilege(current_user, 'siaga.users', 'role', 'UPDATE'),
                has_column_privilege(current_user, 'siaga.users', 'active', 'UPDATE')""")
            ).one()
            if any(unsafe):
                return False
            bad_columns = conn.execute(
                text("""SELECT count(*) FROM information_schema.columns
                WHERE table_schema='siaga' AND table_name='notification_logs'
                AND column_name <> 'read_at' AND has_column_privilege(
                current_user, 'siaga.notification_logs', column_name, 'UPDATE')""")
            ).scalar_one()
            revisions = conn.execute(
                text("SELECT revision, checksum FROM siaga.schema_migrations")
            ).all()
            return not bad_columns and revisions == [(REVISION, migration_checksum())]
    except SQLAlchemyError, OSError:
        return False
