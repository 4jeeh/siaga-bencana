import psycopg
import pytest
from psycopg import sql

from app.db.migrations import REVISION, TABLES, apply_migrations, migration_checksum


def test_migration_integrity(database):
    with psycopg.connect(database["runtime"]) as conn:
        tables = conn.execute("SELECT tablename FROM pg_tables WHERE schemaname='siaga'").fetchall()
        assert {t[0] for t in tables} == TABLES | {"schema_migrations"}
        assert conn.execute(
            "SELECT revision, checksum FROM siaga.schema_migrations"
        ).fetchall() == [(REVISION, migration_checksum())]
        assert (
            conn.execute(
                "SELECT count(*) FROM pg_constraint c JOIN pg_namespace n "
                "ON n.oid=c.connamespace WHERE n.nspname='siaga' "
                "AND c.contype='f'"
            ).fetchone()[0]
            == 13
        )


@pytest.mark.parametrize("table", sorted(TABLES))
@pytest.mark.parametrize("operation", ["DELETE FROM", "TRUNCATE"])
def test_core_delete_truncate_denied(database, table, operation):
    with psycopg.connect(database["runtime"], autocommit=True) as conn:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute(sql.SQL("{} siaga.{}").format(sql.SQL(operation), sql.Identifier(table)))


@pytest.mark.parametrize(
    "statement",
    [
        "UPDATE siaga.report_verifications SET reason='rewrite audit'",
        "UPDATE siaga.notification_logs SET priority_label='high'",
        "UPDATE siaga.users SET role='admin'",
        "UPDATE siaga.users SET active=false",
        "CREATE TABLE siaga.forbidden(id integer)",
        "UPDATE siaga.schema_migrations SET revision='forged'",
        "SET ROLE siaga_owner",
    ],
)
def test_privileged_changes_denied(database, statement):
    with psycopg.connect(database["runtime"], autocommit=True) as conn:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute(statement)


def test_allowed_read_at_only(database):
    with psycopg.connect(database["runtime"]) as conn:
        conn.execute("UPDATE siaga.notification_logs SET read_at=now() WHERE false")
        assert conn.execute("SELECT * FROM siaga.report_verifications").fetchall() == []
        assert conn.execute(
            "SELECT has_table_privilege(current_user, 'siaga.report_verifications','INSERT')"
        ).fetchone()[0]


def test_migration_refuses_drift(database):
    with psycopg.connect(database["owner"], autocommit=True) as owner:
        owner.execute("UPDATE siaga.schema_migrations SET checksum='tampered'")
        try:
            with pytest.raises(RuntimeError, match="modified migration"):
                apply_migrations(database["owner"])
        finally:
            owner.execute("UPDATE siaga.schema_migrations SET checksum=%s", (migration_checksum(),))


def test_grants_reapply_removes_unsafe_column_and_public_acl(database):
    with psycopg.connect(database["owner"]) as owner:
        owner.execute("GRANT UPDATE (reason) ON siaga.report_verifications TO siaga_runtime")
        owner.execute("GRANT USAGE ON SCHEMA siaga TO PUBLIC")
        owner.execute("GRANT SELECT (email) ON siaga.users TO PUBLIC")
    apply_migrations(database["owner"])
    with psycopg.connect(database["runtime"], autocommit=True) as conn:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute("UPDATE siaga.report_verifications SET reason='rewrite audit'")
    with psycopg.connect(database["owner"]) as owner:
        assert (
            owner.execute("""SELECT count(*) FROM pg_attribute a
            JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace,
            LATERAL aclexplode(a.attacl) acl
            WHERE n.nspname='siaga' AND acl.grantee=0""").fetchone()[0]
            == 0
        )
