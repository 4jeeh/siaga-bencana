from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import jwt
import psycopg
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine

from app.core.errors import ApiError
from app.core.rate_limit import RateLimiter


def error(response, status, code):
    assert response.status_code == status, response.text
    payload = response.json()
    assert set(payload) == {"code", "message", "details", "request_id"}
    assert payload["code"] == code
    assert str(UUID(payload["request_id"])) == response.headers["x-request-id"]
    assert response.headers["cache-control"] == "no-store"
    if status == 401:
        assert response.headers["www-authenticate"] == "Bearer"
    assert "password" not in payload.get("message", "")


def test_health_ready(client, app):
    response = client.get("/api/v1/health", headers={"X-Request-ID": "untrusted"})
    assert response.status_code == 200
    assert response.json()["data"] == {"status": "ok"}
    assert response.json()["meta"]["mode"] == "local_live"
    assert response.json()["meta"]["server_time"].endswith("Z")
    UUID(response.headers["x-request-id"])
    response = client.get("/api/v1/ready")
    assert response.status_code == 200, response.text
    assert response.json()["data"] == {"status": "ready"}
    app.state.storage_probe.ok = False
    error(client.get("/api/v1/ready"), 503, "SERVICE_UNAVAILABLE")
    assert client.get("/api/v1/health").status_code == 200


def test_ready_stale_probe(client, app):
    app.state.storage_probe.checked_at -= 61
    error(client.get("/api/v1/ready"), 503, "SERVICE_UNAVAILABLE")


def test_db_down_does_not_break_health(client, app):
    original = app.state.engine
    broken = create_engine(
        "postgresql+psycopg://siaga_runtime@127.0.0.1:1/no_database",
        connect_args={"connect_timeout": 1},
    )
    try:
        app.state.engine = broken
        assert client.get("/api/v1/health").status_code == 200
        error(client.get("/api/v1/ready"), 503, "SERVICE_UNAVAILABLE")
        error(
            client.post(
                "/api/v1/auth/login",
                json={"email": "a@example.test", "password": "valid-pass-long"},
            ),
            503,
            "SERVICE_UNAVAILABLE",
        )
    finally:
        app.state.engine = original
        broken.dispose()


def test_ready_rejects_owner(client, app, database):
    original = app.state.engine
    owner = create_engine(database["owner"].replace("postgresql:", "postgresql+psycopg:"))
    try:
        app.state.engine = owner
        error(client.get("/api/v1/ready"), 503, "SERVICE_UNAVAILABLE")
    finally:
        app.state.engine = original
        owner.dispose()


def test_ready_wrong_revision(client, database):
    with psycopg.connect(database["owner"], autocommit=True) as owner:
        owner.execute("UPDATE siaga.schema_migrations SET revision='not-current'")
        try:
            error(client.get("/api/v1/ready"), 503, "SERVICE_UNAVAILABLE")
        finally:
            owner.execute("UPDATE siaga.schema_migrations SET revision='0001_foundation'")


def test_register_login_me(client, account, database, settings):
    body, auth, headers = account
    assert auth["token_type"] == "bearer" and auth["expires_in"] == settings.jwt_ttl_seconds
    assert auth["user"]["display_name"] == "Warga Demo"
    assert auth["user"]["role"] == "citizen" and auth["user"]["has_zone"] is False
    assert set(auth["user"]) == {"id", "email", "display_name", "role", "has_zone"}
    error(
        client.post("/api/v1/auth/register", json={**body, "email": body["email"].upper()}),
        409,
        "EMAIL_ALREADY_REGISTERED",
    )
    result = client.post(
        "/api/v1/auth/login",
        json={"email": " " + body["email"].upper() + " ", "password": body["password"]},
    )
    assert result.status_code == 200
    assert client.get("/api/v1/me", headers=headers).json()["data"] == auth["user"]
    with psycopg.connect(database["owner"]) as owner:
        row = owner.execute(
            "SELECT password_hash FROM siaga.users WHERE id=%s", (auth["user"]["id"],)
        ).fetchone()
        assert row[0].startswith("$argon2id$") and body["password"] not in row[0]
        owner.execute("UPDATE siaga.users SET role='admin' WHERE id=%s", (auth["user"]["id"],))
        owner.execute(
            "INSERT INTO siaga.alert_zones(user_id,latitude,longitude) VALUES (%s,0,0)",
            (auth["user"]["id"],),
        )
    current = client.get("/api/v1/me", headers=headers).json()["data"]
    assert current["role"] == "admin" and current["has_zone"] is True


@pytest.mark.parametrize(
    "patch",
    [
        {"role": "admin"},
        {"surprise": 1},
        {"password": "short"},
        {"password": "a" * 129},
        {"display_name": " "},
        {"display_name": "a" * 81},
        {"email": "bad"},
        {"email": "a..b@example.test"},
        {"password": 1234567890},
    ],
)
def test_register_validation(client, patch):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "valid@example.test",
            "password": "long-enough-password",
            "display_name": "Warga",
            **patch,
        },
    )
    error(response, 422, "VALIDATION_ERROR")
    assert response.json()["details"]["fields"]
    assert "input" not in response.text and "long-enough-password" not in response.text


def test_wrong_missing_inactive(client, account, database):
    body, auth, headers = account
    for email, password in [
        (body["email"], "wrong-pass-long"),
        (body["email"], body["password"].strip()),
        ("missing@example.test", body["password"]),
    ]:
        error(
            client.post("/api/v1/auth/login", json={"email": email, "password": password}),
            401,
            "INVALID_CREDENTIALS",
        )
    with psycopg.connect(database["owner"]) as owner:
        owner.execute("UPDATE siaga.users SET active=false WHERE id=%s", (auth["user"]["id"],))
    error(
        client.post(
            "/api/v1/auth/login", json={"email": body["email"], "password": body["password"]}
        ),
        401,
        "INVALID_CREDENTIALS",
    )
    error(client.get("/api/v1/me", headers=headers), 401, "TOKEN_INVALID")


@pytest.mark.parametrize(
    "mutation,code",
    [
        ("expired", "TOKEN_EXPIRED"),
        ("issuer", "TOKEN_INVALID"),
        ("audience", "TOKEN_INVALID"),
        ("none", "TOKEN_INVALID"),
        ("sub", "TOKEN_INVALID"),
        ("missing", "TOKEN_INVALID"),
        ("future", "TOKEN_INVALID"),
        ("hs384", "TOKEN_INVALID"),
    ],
)
def test_invalid_tokens(client, account, settings, mutation, code):
    _, data, _ = account
    now = int(datetime.now(UTC).timestamp())
    claims = {
        "sub": data["user"]["id"],
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": now - 100,
        "exp": now + 3500,
    }
    algorithm = "HS256"
    key = settings.jwt_secret.get_secret_value()
    if mutation == "expired":
        claims["exp"] = now - 1
    elif mutation == "issuer":
        claims["iss"] = "wrong"
    elif mutation == "audience":
        claims["aud"] = "wrong"
    elif mutation == "sub":
        claims["sub"] = "not-uuid"
    elif mutation == "missing":
        del claims["exp"]
    elif mutation == "future":
        claims["iat"] = now + 200
    elif mutation == "none":
        algorithm, key = "none", None
    elif mutation == "hs384":
        algorithm = "HS384"
    token = jwt.encode(claims, key, algorithm=algorithm)
    error(client.get("/api/v1/me", headers={"Authorization": "Bearer " + token}), 401, code)


def test_missing_token(client):
    error(client.get("/api/v1/me"), 401, "AUTH_REQUIRED")
    error(client.get("/api/v1/me", headers={"Authorization": "Basic xyz"}), 401, "TOKEN_INVALID")


@pytest.mark.parametrize(
    "path,status,code",
    [
        ("/api/v1/health?a=1", 422, "VALIDATION_ERROR"),
        ("/api/v1/ready?a=1&a=2", 400, "MALFORMED_REQUEST"),
        ("/api/v1/no-such-route", 404, "RESOURCE_NOT_FOUND"),
    ],
)
def test_query_and_http_errors(client, path, status, code):
    error(client.get(path), status, code)


@pytest.mark.parametrize("body", ['{"email":', '{"x":NaN}', '{"x":1,"x":2}', ""])
def test_malformed(client, body):
    error(
        client.post(
            "/api/v1/auth/login", content=body, headers={"Content-Type": "application/json"}
        ),
        400,
        "MALFORMED_REQUEST",
    )


def test_wrong_content_type_body_limit_and_get_body(client):
    error(client.post("/api/v1/auth/login", content="{}"), 415, "UNSUPPORTED_MEDIA_TYPE")
    error(
        client.post(
            "/api/v1/auth/login",
            content=b"x" * 3145729,
            headers={"Content-Type": "application/json"},
        ),
        413,
        "REQUEST_TOO_LARGE",
    )
    error(client.request("GET", "/api/v1/health", content="{}"), 400, "MALFORMED_REQUEST")


def test_unhandled_and_http_exception(client, app):
    @app.get("/crash-test")
    def crash():
        raise RuntimeError("DO-NOT-LEAK-DSN")

    @app.get("/http-error-test")
    def http_error():
        raise HTTPException(403, "DO-NOT-LEAK-DSN")

    for path, status, code in [
        ("/crash-test", 500, "INTERNAL_ERROR"),
        ("/http-error-test", 403, "FORBIDDEN"),
    ]:
        response = client.get(path)
        error(response, status, code)
        assert "DO-NOT-LEAK" not in response.text


def test_login_rate_limit(client):
    for _ in range(5):
        assert (
            client.post(
                "/api/v1/auth/login",
                json={"email": "absent@example.test", "password": "long-password"},
            ).status_code
            == 401
        )
    response = client.post("/api/v1/auth/login", json={}, headers={"X-Forwarded-For": "1.2.3.4"})
    error(response, 429, "RATE_LIMITED")
    assert int(response.headers["retry-after"]) >= 1


def test_register_rate_limit(client):
    for _ in range(3):
        assert client.post("/api/v1/auth/register", json={}).status_code == 422
    response = client.post("/api/v1/auth/register", json={})
    error(response, 429, "RATE_LIMITED")
    assert int(response.headers["retry-after"]) >= 1


def test_read_limit_and_recovery(client, app, account):
    _, _, headers = account
    now = [1000.0]
    app.state.limiter = RateLimiter(clock=lambda: now[0])
    for _ in range(120):
        assert client.get("/api/v1/me", headers=headers).status_code == 200
    response = client.get("/api/v1/me", headers=headers)
    error(response, 429, "RATE_LIMITED")
    now[0] += 60.01
    assert client.get("/api/v1/me", headers=headers).status_code == 200


def test_simulation_does_not_change_token_clock(client, app, account, database):
    # Runtime clock injection isolates business time without provisioning fixtures/events.
    app.state.settings.app_mode = "simulation"
    app.state.settings.simulation_clock = "2020-01-01T00:00:00Z"
    body = {
        "email": f"sim-{uuid4().hex}@example.test",
        "password": "simulation-password",
        "display_name": "Simulation clock test",
    }
    response = client.post("/api/v1/auth/register", json=body)
    assert response.status_code == 201
    assert response.json()["meta"] == {
        "mode": "simulation",
        "is_simulated": True,
        "server_time": "2020-01-01T00:00:00Z",
    }
    expires = datetime.fromisoformat(response.json()["data"]["expires_at"].replace("Z", "+00:00"))
    ttl = timedelta(seconds=app.state.settings.jwt_ttl_seconds)
    assert ttl - timedelta(minutes=1) < expires - datetime.now(UTC) <= ttl
    with psycopg.connect(database["owner"]) as owner:
        created = owner.execute(
            "SELECT created_at FROM siaga.users WHERE email=%s", (body["email"],)
        ).fetchone()[0]
        assert created.year == 2020


def test_limiter_real_window():
    now = [0.0]
    limiter = RateLimiter(clock=lambda: now[0])
    limiter.check("ip", 1)
    with pytest.raises(ApiError):
        limiter.check("ip", 1)
    now[0] = 60
    limiter.check("ip", 1)


def test_concurrent_register_only_one_account(client):
    from concurrent.futures import ThreadPoolExecutor

    body = {
        "email": f"race-{uuid4().hex}@example.test",
        "password": "race-password-long",
        "display_name": "Race Test",
    }
    with ThreadPoolExecutor(max_workers=2) as workers:
        responses = list(
            workers.map(lambda _: client.post("/api/v1/auth/register", json=body), range(2))
        )
    assert sorted(response.status_code for response in responses) == [201, 409]
