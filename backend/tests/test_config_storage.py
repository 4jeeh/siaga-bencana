from pathlib import Path

import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.services.readiness import StorageProbe


@pytest.mark.parametrize(
    "patch",
    [
        {"jwt_secret": "short"},
        {"media_signing_secret": "short"},
        {"jwt_ttl_seconds": 3599},
        {"jwt_ttl_seconds": 604801},
        {"database_url": "sqlite:///local.db"},
        {"database_url": "postgresql+psycopg://postgres@localhost/dev"},
        {"app_mode": "local_live", "simulation_clock": "2020-01-01T00:00:00Z"},
        {"app_mode": "production_live"},
        {"app_mode": "simulation", "simulation_clock": "2020-01-01T00:00:00Z"},
    ],
)
def test_unsafe_environment_rejected(settings, patch):
    data = settings.model_dump()
    with pytest.raises(ValidationError):
        Settings(_env_file=None, **{**data, **patch})


def test_simulation_requires_isolated_database_storage_and_utc(settings, tmp_path):
    data = settings.model_dump()
    data.update(
        app_mode="simulation",
        simulation_clock="2020-01-01T00:00:00Z",
        database_url="postgresql+psycopg://siaga_runtime@localhost/test_simulation",
        storage_root=tmp_path / "simulation",
    )
    simulation = Settings(_env_file=None, **data)
    assert simulation.domain_now().year == 2020
    with pytest.raises(ValidationError):
        Settings(_env_file=None, **{**data, "simulation_clock": "2020-01-01T00:00:00"})
    with pytest.raises(ValidationError):
        Settings(_env_file=None, **{**data, "bmkg_sync_enabled": True})


def test_probe_cleans_object_and_rejects_public_or_invalid_path(settings, tmp_path):
    probe = StorageProbe(settings)
    probe.check()
    assert probe.ready
    assert list(settings.storage_root.iterdir()) == []
    settings.storage_root = tmp_path / "static"
    probe.check()
    assert not probe.ready and not settings.storage_root.exists()
    path = tmp_path / "existing-file"
    path.write_text("not a directory")
    settings.storage_root = path
    probe.check()
    assert not probe.ready
    settings.storage_root = Path(tmp_path.anchor)
    probe.check()
    assert not probe.ready


def test_unimplemented_storage_adapter_never_claims_readiness(settings):
    settings.storage_backend = "supabase"
    probe = StorageProbe(settings)
    probe.check()
    assert not probe.ready


def test_env_example_loads_numeric_ttl_from_dotenv(settings, tmp_path):
    from app.core.config import BACKEND_ROOT

    template = (BACKEND_ROOT / ".env.example").read_text(encoding="utf-8")
    template = template.replace(
        "JWT_SECRET=\n", "JWT_SECRET=" + settings.jwt_secret.get_secret_value() + "\n"
    )
    template = template.replace(
        "MEDIA_SIGNING_SECRET=\n",
        "MEDIA_SIGNING_SECRET=" + settings.media_signing_secret.get_secret_value() + "\n",
    )
    env_file = tmp_path / ".env"
    env_file.write_text(template, encoding="utf-8")
    parsed = Settings(_env_file=env_file)
    assert parsed.jwt_ttl_seconds == 604800
    assert parsed.app_mode == "local_live"
    assert parsed.cors_origins == []
