from unittest.mock import Mock

import httpx
import jwt
import pytest

from app.core.config import Settings
from app.services import radar
from app.services.ttl_cache import TTLCache
from app.services.weather import condition
from tests import test_events_map as maps

db = maps.db
event_database = maps.event_database
map_settings = maps.settings

SEARCH = "/api/v1/locations/search"
WEATHER = "/api/v1/me/weather"
CURRENT = {
    "temperature_2m": 28.5, "relative_humidity_2m": 83, "precipitation": 2.4,
    "wind_speed_10m": 11.2, "weather_code": 95, "time": "2026-11-26T13:00",
}


@pytest.fixture(autouse=True)
def fetch(monkeypatch):
    mock = Mock(side_effect=AssertionError("Unexpected external HTTP request"))
    monkeypatch.setattr(httpx, "get", mock)
    return mock


@pytest.fixture
def zone_headers(client, account):
    maps.zone(client, account[2])
    return account[2]


def payload(client, path, headers, **params):
    response = client.get(path, headers=headers, params=params)
    assert response.status_code == 200, response.text
    return response.json()["data"]


def test_locations_live_cache_and_throttle(client, account, fetch, monkeypatch):
    monkeypatch.setattr("app.services.locations.monotonic", lambda: 30.0)
    fetch.side_effect = None
    fetch.return_value = httpx.Response(200, json=[
        {"display_name": "Bandung, Jawa Barat", "lat": "-6.9175", "lon": "107.6191"}
    ])

    first = payload(client, SEARCH, account[2], q=" Bandung ", limit=1)
    cached = payload(client, SEARCH, account[2], q="BANDUNG", limit=1)
    throttled = payload(client, SEARCH, account[2], q="Bali")

    assert first == cached == {"items": [{
        "source": "NOMINATIM", "label": "Bandung", "subtitle": "Jawa Barat",
        "latitude": -6.9175, "longitude": 107.6191,
    }]}
    assert throttled["items"][0]["source"] == "LOCAL_FALLBACK"
    fetch.assert_called_once_with(
        "https://nominatim.openstreetmap.org/search",
        params={
            "q": "Bandung", "format": "jsonv2", "addressdetails": "1", "countrycodes": "id",
            "accept-language": "id", "limit": "1",
        },
        headers={"User-Agent": "SiagaBencana/1.0 (UAS Pemrograman Aplikasi Bergerak)"},
        timeout=4.0, follow_redirects=False,
    )


@pytest.mark.parametrize("result", [
    httpx.ReadTimeout("offline"), httpx.Response(503), httpx.Response(200, json=[]),
    httpx.Response(200, content=b"{"), httpx.Response(200, json=[{"display_name": "Bogor"}]),
])
def test_locations_fallback(client, account, fetch, result):
    fetch.side_effect = [result]
    data = payload(client, SEARCH, account[2], q="BoGoR")
    assert [i["label"] for i in data["items"]] == ["Bogor"]
    assert data["items"][0]["source"] == "LOCAL_FALLBACK"


def test_location_validation_and_auth(client, account, fetch):
    for params in ({"q": " a "}, {"q": "x" * 101}, {"q": "ab", "extra": 1},
                   {"q": "ab", "limit": 11}, {"q": "ab", "limit": 0}):
        response = client.get(SEARCH, headers=account[2], params=params)
        assert (response.status_code, response.json()["code"]) == (422, "VALIDATION_ERROR")
    assert client.get(SEARCH, params={"q": "Bogor"}).status_code == 401
    fetch.assert_not_called()


def test_simulation(client, settings, zone_headers, fetch):
    settings.app_mode = "simulation"
    settings.simulation_clock = maps.NOW.isoformat()

    places = payload(client, SEARCH, zone_headers, q="Dki JaKarta", limit=2)["items"]
    assert len(places) == 2 and all(p["source"] == "LOCAL_FALLBACK" for p in places)
    assert payload(client, SEARCH, zone_headers, q="zzzzz") == {"items": []}
    assert payload(client, WEATHER, zone_headers) is None
    fetch.assert_not_called()


class TestMapMarkers:
    # The map fixtures reset their own isolated simulation database for each test.
    @pytest.fixture
    def settings(self, map_settings):
        return map_settings

    def test_marker_fields(self, client, account, zone_headers, db):
        quake = maps.event(db, "Gempa", magnitude=5.2, depth_km=12, potential="Tidak tsunami")
        polygon = radar.analyze_polygon([(-0.1, -0.1), (0.1, -0.1), (0, 0.1)])
        weather = maps.cap(db, "Hujan", [("Zona", [polygon])])
        reports = maps.seed_reports(db, account[1]["user"]["id"])
        db.commit()

        response = client.get(maps.MAP, headers=zone_headers)
        assert response.status_code == 200, response.text
        fields = ("magnitude", "depth_km", "potential")
        markers = {r["id"]: tuple(r[k] for k in fields) for r in response.json()["items"]}
        assert markers[str(quake.id)] == (5.2, 12, "Tidak tsunami")
        assert markers[str(weather.id)] == (None, None, None)
        assert all(markers[str(id_)] == (None, None, None) for id_ in reports)


def test_weather_requires_zone(client, account, fetch):
    response = client.get(WEATHER, headers=account[2])
    assert (response.status_code, response.json()["code"]) == (409, "ZONE_REQUIRED")
    assert response.json()["details"] == {"action": "setup_zone"}
    assert client.get(WEATHER).status_code == 401
    assert client.get(WEATHER, headers=account[2], params={"q": "ab"}).status_code == 422
    fetch.assert_not_called()


def test_weather_live_and_cached(client, zone_headers, fetch):
    fetch.side_effect = [httpx.Response(200, json={"current": CURRENT})]

    fresh = payload(client, WEATHER, zone_headers)
    cached = payload(client, WEATHER, zone_headers)

    assert fresh == {
        "temperature_c": 28.5, "humidity_percent": 83, "precipitation_mm": 2.4,
        "wind_speed_kmh": 11.2, "weather_code": 95, "condition_code": "thunderstorm",
        "condition_label": "Hujan petir", "observed_at": CURRENT["time"],
        "source": "OPEN_METEO", "is_cached": False,
    }
    assert cached == {**fresh, "is_cached": True}
    fetch.assert_called_once_with(
        "https://api.open-meteo.com/v1/forecast",
        params={"latitude": "0.0000", "longitude": "0.0000", "timezone": "auto",
                "current": "temperature_2m,relative_humidity_2m,precipitation,"
                           "weather_code,wind_speed_10m"},
        timeout=4.0, follow_redirects=False,
    )


@pytest.mark.parametrize("result", [
    httpx.ReadTimeout("offline"), httpx.Response(500), httpx.Response(200, content=b"{"),
    httpx.Response(200, json={"current": {}}),
    httpx.Response(200, json={"current": {**CURRENT, "temperature_2m": "invalid"}}),
])
def test_weather_unavailable(client, zone_headers, fetch, result):
    fetch.side_effect = [result]
    assert payload(client, WEATHER, zone_headers) is None


@pytest.mark.parametrize(("codes", "expected"), [
    ([0], ("clear", "Cerah")), ([1, 2], ("partly_cloudy", "Cerah berawan")),
    ([3], ("cloudy", "Berawan")), ([45, 48], ("fog", "Berkabut")),
    ([51, 53, 55, 56, 57], ("drizzle", "Gerimis")), ([61, 63, 66, 80, 81], ("rain", "Hujan")),
    ([65, 67, 82], ("heavy_rain", "Hujan lebat")), ([95, 96, 99], ("thunderstorm", "Hujan petir")),
    ([100], ("unknown", "Cuaca bervariasi")),
])
def test_wmo_codes(codes, expected):
    assert all(condition(code) == expected for code in codes)


@pytest.mark.parametrize(("service", "ttl"), [("locations", 900), ("weather", 600)])
def test_provider_cache_expires(app, monkeypatch, service, ttl):
    now = 10.0
    monkeypatch.setattr("app.services.ttl_cache.monotonic", lambda: now)
    cache = getattr(app.state, service).cache
    cache.put("key", "result")

    now += ttl - 1
    assert cache.get("key") == "result"
    now += 1
    assert cache.get("key") is None


def test_provider_cache_capacity():
    cache = TTLCache[int, int](600)
    for key in range(257):
        cache.put(key, key)
    assert cache.get(0) is None
    assert all(cache.get(key) == key for key in range(1, 257))


@pytest.mark.parametrize("ttl", [604800, 7200])
def test_login_uses_configured_ttl(client, account, app, settings, ttl):
    config = Settings(_env_file=None, **(settings.model_dump() | {"jwt_ttl_seconds": ttl}))
    app.state.settings = config
    body = account[0]

    response = client.post("/api/v1/auth/login", json={
        "email": body["email"], "password": body["password"],
    })

    assert response.status_code == 200
    data = response.json()["data"]
    claims = jwt.decode(
        data["access_token"], config.jwt_secret.get_secret_value(), algorithms=["HS256"],
        audience=config.jwt_audience, issuer=config.jwt_issuer,
    )
    assert data["expires_in"] == claims["exp"] - claims["iat"] == config.jwt_ttl_seconds == ttl
