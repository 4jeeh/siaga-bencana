import json
import math
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import psycopg
import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.schemas.zone import ZoneRequest
from tests.test_api import error

PATH = "/api/v1/me/zone"
ZONE = {
    "latitude": -7.25,
    "longitude": 112.75,
    "radius_km": 50,
    "notify_earthquake": True,
    "notify_weather": True,
}
DTO_FIELDS = set(ZONE) | {"id", "zone_version", "alert_eligible_since", "updated_at"}


def put_zone(client, headers, body):
    response = client.put(PATH, headers=headers, json=body)
    assert response.status_code == 200, response.text
    assert response.headers["cache-control"] == "no-store"
    payload = response.json()
    assert set(payload) == {"data", "meta"}
    assert set(payload["data"]) == DTO_FIELDS
    UUID(payload["data"]["id"])
    return payload["data"]


def test_zone_lifecycle(client, account, monkeypatch, database):
    body, auth, headers = account
    clock = [datetime(2030, 1, 1, tzinfo=UTC)]
    monkeypatch.setattr(Settings, "domain_now", lambda self: clock[0])
    response = client.get(PATH, headers=headers)
    assert response.status_code == 200
    assert response.json()["data"] is None
    assert client.get("/api/v1/me", headers=headers).json()["data"]["has_zone"] is False

    created = put_zone(client, headers, ZONE)
    assert {key: created[key] for key in ZONE} == ZONE
    assert created["zone_version"] == 1
    assert created["updated_at"] == created["alert_eligible_since"] == "2030-01-01T00:00:00Z"
    assert client.get("/api/v1/me", headers=headers).json()["data"]["has_zone"] is True
    login = client.post(
        "/api/v1/auth/login", json={"email": body["email"], "password": body["password"]}
    )
    assert login.status_code == 200
    assert login.json()["data"]["user"]["has_zone"] is True
    assert client.get(PATH, headers=headers).json()["data"] == created

    clock[0] += timedelta(minutes=1)
    assert put_zone(client, headers, ZONE) == created
    assert client.get(PATH, headers=headers).json()["data"] == created
    with psycopg.connect(database["owner"]) as owner:
        row = owner.execute(
            "SELECT created_at, updated_at, alert_eligible_since FROM siaga.alert_zones "
            "WHERE user_id=%s", (auth["user"]["id"],)
        ).fetchone()
    assert row == (datetime(2030, 1, 1, tzinfo=UTC),) * 3


@pytest.mark.parametrize(
    "patch",
    [
        {"radius_km": 25},
        {"radius_km": 100},
        {"notify_earthquake": False},
        {"notify_weather": False},
        {"latitude": -8},
        {"longitude": 113},
    ],
)
def test_each_real_change_advances_version(client, account, monkeypatch, patch):
    headers = account[2]
    clock = [datetime(2030, 1, 1, tzinfo=UTC)]
    monkeypatch.setattr(Settings, "domain_now", lambda self: clock[0])
    created = put_zone(client, headers, ZONE)
    clock[0] += timedelta(minutes=1)
    updated = put_zone(client, headers, {**ZONE, **patch})
    assert updated["id"] == created["id"]
    assert updated["zone_version"] == 2
    assert updated["updated_at"] == updated["alert_eligible_since"] == "2030-01-01T00:01:00Z"
    assert {key: updated[key] for key in ZONE} == {**ZONE, **patch}
    assert client.get(PATH, headers=headers).json()["data"] == updated
    clock[0] += timedelta(minutes=1)
    assert put_zone(client, headers, {**ZONE, **patch}) == updated


@pytest.mark.parametrize("latitude,longitude", [(0, 0), (-7, 0), (-90, -180), (90, 180)])
def test_integer_coordinates_and_global_bounds(client, account, latitude, longitude):
    zone = put_zone(client, account[2], {**ZONE, "latitude": latitude, "longitude": longitude})
    assert zone["latitude"] == latitude
    assert zone["longitude"] == (-180 if longitude == 180 else longitude)


@pytest.mark.parametrize("longitude", [180.0, -0.0])
def test_canonical_equivalent_is_noop(client, account, monkeypatch, longitude):
    clock = [datetime(2030, 1, 1, tzinfo=UTC)]
    monkeypatch.setattr(Settings, "domain_now", lambda self: clock[0])
    body = {**ZONE, "latitude": -0.0, "longitude": longitude}
    created = put_zone(client, account[2], body)
    assert math.copysign(1, created["latitude"]) == 1
    expected_lon = -180.0 if longitude == 180 else 0.0
    assert created["longitude"] == expected_lon
    if expected_lon == 0:
        assert math.copysign(1, created["longitude"]) == 1
    clock[0] += timedelta(minutes=1)
    canonical = {**body, "latitude": 0, "longitude": expected_lon}
    assert put_zone(client, account[2], canonical) == created
    assert client.get(PATH, headers=account[2]).json()["data"] == created


@pytest.mark.parametrize(
    "field,value",
    [(field, value) for field in ("latitude", "longitude", "radius_km")
     for value in (True, False, "0", None)]
    + [("latitude", -90.001), ("latitude", 90.001),
       ("longitude", -180.001), ("longitude", 180.001)]
    + [("radius_km", value) for value in (0, -25, 26, 51, 101, 25.0, "25")]
    + [(field, value) for field in ("notify_earthquake", "notify_weather")
       for value in (0, 1, "true", None)]
    + [(field, "forbidden") for field in (
        "zone_version", "alert_eligible_since", "updated_at", "created_at", "id", "user_id",
    )],
)
def test_zone_rejects_invalid_and_extra_fields(client, account, field, value):
    headers = account[2]
    created = put_zone(client, headers, ZONE)
    response = client.put(PATH, headers=headers, json={**ZONE, field: value})
    error(response, 422, "VALIDATION_ERROR")
    assert response.json()["details"]["fields"]
    assert client.get(PATH, headers=headers).json()["data"] == created


@pytest.mark.parametrize("missing", list(ZONE))
def test_full_replacement_requires_every_field(client, account, missing):
    body = {key: value for key, value in ZONE.items() if key != missing}
    error(client.put(PATH, headers=account[2], json=body), 422, "VALIDATION_ERROR")
    assert client.get(PATH, headers=account[2]).json()["data"] is None


@pytest.mark.parametrize("field", ["latitude", "longitude"])
@pytest.mark.parametrize("value", [float("nan"), float("inf"), -float("inf")])
def test_nonfinite_coordinates_rejected(client, account, field, value):
    body = {**ZONE, field: value}
    with pytest.raises(ValidationError):
        ZoneRequest.model_validate(body)
    # Non-standard JSON constants are malformed at the shared middleware layer.
    response = client.put(
        PATH, headers={**account[2], "Content-Type": "application/json"},
        content=json.dumps(body),
    )
    error(response, 400, "MALFORMED_REQUEST")


@pytest.mark.parametrize("field", ["latitude", "longitude"])
def test_overflowing_json_number_rejected(client, account, field):
    body = json.dumps({**ZONE, field: "overflow"}).replace('"overflow"', "1e999")
    response = client.put(
        PATH, headers={**account[2], "Content-Type": "application/json"}, content=body
    )
    error(response, 422, "VALIDATION_ERROR")


def test_zone_requires_auth(client):
    error(client.get(PATH), 401, "AUTH_REQUIRED")
    error(client.put(PATH, json=ZONE), 401, "AUTH_REQUIRED")


@pytest.mark.parametrize("body", ['{"latitude":', '{"latitude":0,"latitude":1}', ""])
def test_zone_malformed_json(client, account, body):
    error(client.put(
        PATH, headers={**account[2], "Content-Type": "application/json"}, content=body,
    ), 400, "MALFORMED_REQUEST")


def test_zone_requires_json_content_type(client, account):
    error(client.put(PATH, headers=account[2], content=json.dumps(ZONE)),
          415, "UNSUPPORTED_MEDIA_TYPE")


def test_zone_isolation_and_admin_access(client, account, database):
    first_headers = account[2]
    first = put_zone(client, first_headers, ZONE)
    response = client.post("/api/v1/auth/register", json={
        "email": f"other-{uuid4().hex}@example.test",
        "password": "other-password-long",
        "display_name": "Other user",
    })
    assert response.status_code == 201
    auth = response.json()["data"]
    second_headers = {"Authorization": "Bearer " + auth["access_token"]}
    with psycopg.connect(database["owner"]) as owner:
        owner.execute("UPDATE siaga.users SET role='admin' WHERE id=%s", (auth["user"]["id"],))
    assert client.get(PATH, headers=second_headers).json()["data"] is None
    second_body = {**ZONE, "latitude": 45, "radius_km": 100}
    second = put_zone(client, second_headers, second_body)
    assert second["id"] != first["id"]
    error(client.put(PATH, headers=second_headers, json={
        **second_body, "user_id": account[1]["user"]["id"],
    }), 422, "VALIDATION_ERROR")
    error(client.get(PATH + "?user_id=" + account[1]["user"]["id"], headers=second_headers),
          422, "VALIDATION_ERROR")
    put_zone(client, second_headers, {**second_body, "notify_weather": False})
    assert client.get(PATH, headers=first_headers).json()["data"] == first
    assert client.get(PATH, headers=second_headers).json()["data"]["zone_version"] == 2


def test_simulation_zone_business_clock(client, app, account, database):
    # Same runtime clock injection as test_api; JWT still uses the wall clock.
    app.state.settings.app_mode = "simulation"
    app.state.settings.simulation_clock = "2020-01-01T00:00:00Z"
    created = put_zone(client, account[2], ZONE)
    assert created["alert_eligible_since"] == created["updated_at"] == "2020-01-01T00:00:00Z"
    app.state.settings.simulation_clock = "2020-01-02T00:00:00Z"
    assert put_zone(client, account[2], ZONE) == created
    updated = put_zone(client, account[2], {**ZONE, "radius_km": 25})
    assert updated["zone_version"] == 2
    assert updated["alert_eligible_since"] == updated["updated_at"] == "2020-01-02T00:00:00Z"
    with psycopg.connect(database["owner"]) as owner:
        row = owner.execute(
            "SELECT created_at, updated_at, alert_eligible_since FROM siaga.alert_zones "
            "WHERE user_id=%s", (account[1]["user"]["id"],)
        ).fetchone()
    assert row == (datetime(2020, 1, 1, tzinfo=UTC),) + (datetime(2020, 1, 2, tzinfo=UTC),) * 2
    response = client.get(PATH, headers=account[2])
    assert response.json()["meta"] == {
        "mode": "simulation", "is_simulated": True, "server_time": "2020-01-02T00:00:00Z",
    }


@pytest.mark.parametrize("identical", [True, False])
def test_concurrent_zone_creation_serializes(client, account, identical):
    bodies = [ZONE, ZONE if identical else {**ZONE, "radius_km": 25}]
    with ThreadPoolExecutor(max_workers=2) as workers:
        responses = list(workers.map(
            lambda body: client.put(PATH, headers=account[2], json=body), bodies
        ))
    assert [response.status_code for response in responses] == [200, 200]
    snapshots = [response.json()["data"] for response in responses]
    assert snapshots[0]["id"] == snapshots[1]["id"]
    assert sorted(zone["zone_version"] for zone in snapshots) == ([1, 1] if identical else [1, 2])
    for body, snapshot in zip(bodies, snapshots, strict=True):
        assert {key: snapshot[key] for key in ZONE} == body
    final = client.get(PATH, headers=account[2]).json()["data"]
    assert final == max(snapshots, key=lambda zone: zone["zone_version"])
