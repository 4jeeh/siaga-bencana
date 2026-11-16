"""Owner-only migration runner. Never called by the runtime application."""

import hashlib
from pathlib import Path

import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parents[3]
REVISION = "0001_foundation"
TABLES = frozenset(
    {
        "users",
        "alert_zones",
        "disaster_events",
        "event_areas",
        "area_polygons",
        "polygon_vertices",
        "event_references",
        "citizen_reports",
        "report_verifications",
        "notification_logs",
        "sync_runs",
        "media_cleanup_jobs",
    }
)


def migration_source():
    return (ROOT / "docs/ERD.sql").read_text(encoding="utf-8")


def migration_checksum():
    return hashlib.sha256(migration_source().encode()).hexdigest()


def apply_migrations(dsn, runtime_role="siaga_runtime"):
    with psycopg.connect(dsn) as conn:
        conn.execute("SELECT pg_advisory_xact_lock(17261117)")
        exists = conn.execute("SELECT to_regclass('siaga.schema_migrations')").fetchone()[0]
        if exists:
            rows = conn.execute("SELECT revision, checksum FROM siaga.schema_migrations").fetchall()
            if rows != [(REVISION, migration_checksum())]:
                raise RuntimeError("Unknown or modified migration; manual review required")
        else:
            if conn.execute("SELECT to_regnamespace('siaga')").fetchone()[0]:
                raise RuntimeError("Untracked siaga schema; refusing to overwrite it")
            # ERD's outer transaction is replaced by this single atomic transaction.
            source = migration_source().replace("BEGIN;\n", "", 1).replace("COMMIT;\n", "", 1)
            conn.execute(source)
            conn.execute("""CREATE TABLE siaga.schema_migrations (
                revision text PRIMARY KEY, checksum text NOT NULL,
                applied_at timestamptz NOT NULL DEFAULT now())""")
            conn.execute(
                "INSERT INTO siaga.schema_migrations(revision, checksum) VALUES (%s,%s)",
                (REVISION, migration_checksum()),
            )
        grant_runtime(conn, runtime_role)


def grant_runtime(conn, role):
    role_id = sql.Identifier(role)
    info = conn.execute(
        """SELECT rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls
                           FROM pg_roles WHERE rolname=%s""",
        (role,),
    ).fetchone()
    if not info or any(info):
        raise RuntimeError("Runtime role must exist without elevated attributes")
    if conn.execute("SELECT pg_has_role(%s, current_user, 'MEMBER')", (role,)).fetchone()[0]:
        raise RuntimeError("Runtime cannot be a member of the migration owner")
    for grantee in ["PUBLIC", "anon", "authenticated", role]:
        if (
            grantee != "PUBLIC"
            and not conn.execute("SELECT 1 FROM pg_roles WHERE rolname=%s", (grantee,)).fetchone()
        ):
            continue
        identifier = sql.SQL("PUBLIC") if grantee == "PUBLIC" else sql.Identifier(grantee)
        for target in [
            "SCHEMA siaga",
            "ALL TABLES IN SCHEMA siaga",
            "ALL FUNCTIONS IN SCHEMA siaga",
            "ALL SEQUENCES IN SCHEMA siaga",
        ]:
            conn.execute(sql.SQL("REVOKE ALL ON {} FROM {}").format(sql.SQL(target), identifier))
        # Table-level REVOKE does not remove pre-existing column ACLs.
        columns = conn.execute("""SELECT table_name, column_name
            FROM information_schema.columns WHERE table_schema='siaga'""").fetchall()
        for table, column in columns:
            conn.execute(
                sql.SQL("REVOKE ALL ({}) ON siaga.{} FROM {}").format(
                    sql.Identifier(column), sql.Identifier(table), identifier
                )
            )
        conn.execute(
            sql.SQL("ALTER DEFAULT PRIVILEGES IN SCHEMA siaga REVOKE ALL ON TABLES FROM {}").format(
                identifier
            )
        )
        conn.execute(
            sql.SQL(
                "ALTER DEFAULT PRIVILEGES IN SCHEMA siaga REVOKE EXECUTE ON FUNCTIONS FROM {}"
            ).format(identifier)
        )
    conn.execute(sql.SQL("GRANT USAGE ON SCHEMA siaga TO {}").format(role_id))
    conn.execute(sql.SQL("GRANT SELECT ON ALL TABLES IN SCHEMA siaga TO {}").format(role_id))
    # Explicit grants: no DDL, DELETE, TRUNCATE, role escalation, or audit rewrite.
    for table in sorted(TABLES):
        conn.execute(
            sql.SQL("GRANT INSERT ON siaga.{} TO {}").format(sql.Identifier(table), role_id)
        )
    updates = {
        "users": "display_name, password_hash, last_notification_sequence, updated_at",
        "alert_zones": "latitude, longitude, radius_km, notify_earthquake, notify_weather, "
        "zone_version, alert_eligible_since, updated_at",
        "citizen_reports": "status, reviewer_id, version, claimed_at, decided_at, updated_at",
        "notification_logs": "read_at",
    }
    for table, columns in updates.items():
        conn.execute(
            sql.SQL("GRANT UPDATE ({}) ON siaga.{} TO {}").format(
                sql.SQL(columns), sql.Identifier(table), role_id
            )
        )
    for table in TABLES - set(updates) - {"report_verifications"}:
        conn.execute(
            sql.SQL("GRANT UPDATE ON siaga.{} TO {}").format(sql.Identifier(table), role_id)
        )
    conn.execute(sql.SQL("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA siaga TO {}").format(role_id))
