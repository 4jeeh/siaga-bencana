import asyncio
import json
import socket
import time
from contextlib import asynccontextmanager
from urllib.parse import urlencode
from uuid import UUID, uuid4

import httpx
import jwt
import psycopg
import pytest
import uvicorn
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.exc import OperationalError

from app.main import create_app
from app.repositories import notifications as repo
from app.schemas.notifications import MAX_SEQUENCE
from tests import test_notifications_sync as sync
from tests.test_api import error

# Reuse the isolated PostgreSQL, per-test reset, zone and domain-clock fixtures from Slice 5-1.
notification_database = sync.notification_database
database = sync.database
clock = sync.clock
STREAM = sync.HISTORY + "/stream"


class StreamResponse:
    def __init__(self, start, outgoing):
        self.status = start["status"]
        self.headers = httpx.Headers(start["headers"])
        self.outgoing = outgoing
        self.buffer = b""

    async def body(self):
        message = await asyncio.wait_for(self.outgoing.get(), 5)
        assert message["type"] == "http.response.body"
        return message

    async def frame(self):
        assert self.status == 200
        while b"\n\n" not in self.buffer:
            message = await self.body()
            assert message.get("more_body"), "EOF before a complete SSE frame"
            self.buffer += message["body"]
        raw, self.buffer = self.buffer.split(b"\n\n", 1)
        return raw.decode().splitlines()

    async def eof(self):
        assert self.buffer == b""
        message = await self.body()
        assert message["body"] == b"" and not message.get("more_body")

    async def expect_error(self, status, code):
        assert self.status == status
        assert self.headers["content-type"] == "application/json"
        body = bytearray()
        while True:
            message = await self.body()
            body.extend(message["body"])
            if not message.get("more_body"):
                break
        response = httpx.Response(status, headers=self.headers, content=bytes(body))
        error(response, status, code)
        return response


@asynccontextmanager
async def open_stream(app, headers, params=None):
    incoming, outgoing = asyncio.Queue(), asyncio.Queue()
    incoming.put_nowait({"type": "http.request", "body": b"", "more_body": False})
    scope = {
        "type": "http", "asgi": {"version": "3.0", "spec_version": "2.3"},
        "method": "GET", "http_version": "1.1", "scheme": "http",
        "path": STREAM, "raw_path": STREAM.encode(), "root_path": "",
        "query_string": urlencode(params or {}).encode(),
        "headers": [(k.lower(), v) for k, v in httpx.Headers(headers).raw],
        "client": ("127.0.0.1", 12345), "server": ("localhost", 80),
    }
    task = asyncio.create_task(app(scope, incoming.get, outgoing.put))
    try:
        start = await asyncio.wait_for(outgoing.get(), 5)
        assert start["type"] == "http.response.start"
        yield StreamResponse(start, outgoing)
    finally:
        incoming.put_nowait({"type": "http.disconnect"})
        await asyncio.wait_for(task, 5)


def check_connected(frame, owner, since, hwm, heartbeat=20):
    assert frame[:2] == ["retry: 3000", "event: connected"]
    assert len(frame) == 3 and frame[2].startswith("data: ")
    assert json.loads(frame[2][6:]) == {
        "cursor_user_id": owner, "since_sequence": since, "high_water_mark": hwm,
        "heartbeat_seconds": heartbeat, "is_simulated": False,
    }


def check_alert(frame, owner, item):
    assert frame[:2] == [f"id: {owner}:{item['sequence']}", "event: alert"]
    assert len(frame) == 3 and frame[2].startswith("data: ")
    assert json.loads(frame[2][6:]) == item


def signed_headers(account, settings, expires):
    claims = {
        "sub": account[1]["user"]["id"], "iat": expires - 3600, "exp": expires,
        "iss": settings.jwt_issuer, "aud": settings.jwt_audience,
    }
    token = jwt.encode(claims, settings.jwt_secret.get_secret_value(), algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def test_cors_allows_resume_header(settings):
    origin = "http://localhost:8080"
    app = create_app(settings.model_copy(update={"cors_origins": [origin]}))
    with TestClient(app) as client:
        response = client.options(STREAM, headers={
            "Origin": origin, "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization,last-event-id",
        })
    assert response.status_code == 200
    allowed = response.headers["access-control-allow-headers"].lower().split(", ")
    assert {"authorization", "last-event-id"}.issubset(allowed)


def test_auth_and_read_budget(app, account, settings, database):
    params = sync.cursor(account, 0)
    owner = params["cursor_user_id"]

    async def run():
        for headers, code in (
            ({}, "AUTH_REQUIRED"), ({"Authorization": "Bearer invalid"}, "TOKEN_INVALID"),
            (signed_headers(account, settings, int(time.time()) - 1), "TOKEN_EXPIRED"),
        ):
            async with open_stream(app, headers, params) as response:
                await response.expect_error(401, code)
        with psycopg.connect(database["owner"]) as conn:
            conn.execute("UPDATE siaga.users SET active=false WHERE id=%s", (owner,))
        async with open_stream(app, account[2], params) as response:
            await response.expect_error(401, "TOKEN_INVALID")
        with psycopg.connect(database["owner"]) as conn:
            conn.execute("UPDATE siaga.users SET active=true WHERE id=%s", (owner,))
        for _ in range(120):
            app.state.limiter.check(f"read:{owner}", 120)
        async with open_stream(app, account[2], params) as response:
            failure = await response.expect_error(429, "RATE_LIMITED")
            assert int(failure.headers["retry-after"]) >= 1

    asyncio.run(run())


def test_invalid_cursor_and_conflicts(app, account):
    valid = sync.cursor(account, 0)
    owner = valid["cursor_user_id"]
    other = str(uuid4())
    bad_sequences = ("", "00", "-1", "+1", "1.0", str(MAX_SEQUENCE + 1))
    bad_owners = ("", "ABCDEF01-1111-2222-3333-0123456789AB", UUID(owner).hex)

    async def check(params, headers, status, code):
        async with open_stream(app, headers, params) as response:
            failure = await response.expect_error(status, code)
            if status == 409:
                assert failure.json()["details"] == {"action": "fetch_baseline"}

    async def run():
        for params in (
            {}, {"since_sequence": "0"}, {"cursor_user_id": owner}, {**valid, "extra": "1"},
            *({**valid, "since_sequence": value} for value in bad_sequences),
            *({**valid, "cursor_user_id": value} for value in bad_owners),
        ):
            await check(params, account[2], 422, "VALIDATION_ERROR")
        for raw in ("", "1", owner, f"{owner}:0:0", *(f"{owner}:{s}" for s in bad_sequences),
                    *(f"{s}:0" for s in bad_owners)):
            await check(valid, {**account[2], "Last-Event-ID": raw}, 422, "VALIDATION_ERROR")
        await check(valid, [*account[2].items(), ("Last-Event-ID", f"{owner}:0"),
                            ("Last-Event-ID", f"{owner}:0")], 422, "VALIDATION_ERROR")
        await check([*valid.items(), ("since_sequence", "0")], account[2], 400, "MALFORMED_REQUEST")
        for uid, sequence, code in ((other, 1, "CURSOR_USER_MISMATCH"),
                                    (owner, 1, "CURSOR_OUT_OF_RANGE")):
            await check({"cursor_user_id": uid, "since_sequence": sequence}, account[2], 409, code)
            await check(valid, {**account[2], "Last-Event-ID": f"{uid}:{sequence}"}, 409, code)
        async with open_stream(app, account[2], valid) as response:
            check_connected(await response.frame(), owner, 0, 0)

    asyncio.run(run())


def test_preflight_gap_even_before_resume_cursor(app, database, account, clock):
    owner = account[1]["user"]["id"]
    sync.publish(app, sync.quakes(3))
    with psycopg.connect(database["owner"]) as conn:
        conn.execute(
            "DELETE FROM siaga.notification_logs WHERE user_id=%s AND sequence=1", (owner,)
        )

    async def run():
        for _ in range(2):  # Failed preflight must release its reservation.
            async with open_stream(app, account[2], sync.cursor(account, 3)) as response:
                await response.expect_error(503, "SERVICE_UNAVAILABLE")

    asyncio.run(run())


def test_stream_limit_disconnect_and_heartbeat(app, client, account, clock):
    owner = account[1]["user"]["id"]
    params = sync.cursor(account, 0)
    other = client.post("/api/v1/auth/register", json={
        **account[0], "email": f"{uuid4()}@example.test",
    }).json()["data"]
    other_id = other["user"]["id"]
    app.state.stream_poll_seconds = 60
    app.state.stream_heartbeat_seconds = 0.02

    async def run():
        async with open_stream(app, account[2], params) as first:
            check_connected(await first.frame(), owner, 0, 0, 0.02)
            async with open_stream(app, account[2], params) as second:
                failure = await second.expect_error(429, "STREAM_LIMIT_REACHED")
                assert int(failure.headers["retry-after"]) >= 1
            async with open_stream(app, {
                "Authorization": "Bearer " + other["access_token"],
                "Last-Event-ID": f"{other_id}:0",
            }) as independent:
                check_connected(await independent.frame(), other_id, 0, 0, 0.02)
                assert app.state.engine.pool.checkedout() == 0
                heartbeat = await first.frame()
                assert heartbeat[:2] == [": keepalive", "event: heartbeat"]
                assert len(heartbeat) == 3 and heartbeat[2].startswith("data: ")
                assert json.loads(heartbeat[2][6:]) == {"server_time": "2030-01-01T00:00:00Z"}
        async with open_stream(app, account[2], params) as resumed:
            check_connected(await resumed.frame(), owner, 0, 0, 0.02)

    asyncio.run(run())


@pytest.mark.parametrize(("configured", "limit"), [(20, 20), (99, 50)])
def test_ordered_replay_then_live(app, client, account, clock, monkeypatch, configured, limit):
    assert app.state.stream_batch_size == 20
    app.state.stream_batch_size = configured
    app.state.stream_poll_seconds = 0.02
    owner = account[1]["user"]["id"]
    records = sync.quakes(limit + 4)
    sync.publish(app, records[:-1])
    history = sync.get_json(client, sync.HISTORY, account[2], limit=50)["items"]
    history += sync.get_json(client, sync.HISTORY, account[2], offset=50)["items"]
    batches = []
    read_rows = repo.catch_up_rows

    def observe(session, user_id, since, hwm, size):
        assert session.execute(text("SHOW transaction_isolation")).scalar_one() == "repeatable read"
        assert session.execute(text("SHOW transaction_read_only")).scalar_one() == "on"
        rows = read_rows(session, user_id, since, hwm, size)
        batches.append((since, size, len(rows)))
        return rows

    monkeypatch.setattr(repo, "catch_up_rows", observe)

    async def run():
        # Even malformed values in known query cursor fields lose to a valid header.
        async with open_stream(app, {**account[2], "Last-Event-ID": f"{owner}:1"},
                               {"since_sequence": "bad", "cursor_user_id": "bad"}) as stream:
            check_connected(await stream.frame(), owner, 1, len(history))
            read_requests = len(app.state.limiter.buckets[f"read:{owner}"])
            for item in list(reversed(history))[1:]:
                check_alert(await stream.frame(), owner, item)
            assert batches == [(1, limit, limit), (1 + limit, limit, 2)]
            await asyncio.to_thread(sync.publish, app, records[-1:])
            frame = await stream.frame()
            assert len(app.state.limiter.buckets[f"read:{owner}"]) == read_requests
            live = sync.get_json(client, sync.HISTORY, account[2], limit=1)["items"][0]
            assert live["sequence"] == len(history) + 1 and live["read_at"] is None
            check_alert(frame, owner, live)
            assert batches[-1] == (len(history), limit, 1)

    asyncio.run(run())


def test_expiry_wakes_idle_stream(app, account, settings, clock):
    # No poll/heartbeat is due before expiry. The domain clock is frozen years ahead.
    app.state.stream_poll_seconds = 60
    params = sync.cursor(account, 0)

    async def run():
        expires = int(time.time()) + 3
        async with open_stream(app, signed_headers(account, settings, expires), params) as stream:
            check_connected(await stream.frame(), params["cursor_user_id"], 0, 0)
            await stream.eof()
            assert time.time() >= expires
        async with open_stream(app, account[2], params) as stream:
            check_connected(await stream.frame(), params["cursor_user_id"], 0, 0)

    asyncio.run(run())


@pytest.mark.parametrize("reason", ["inactive", "gap", "database", "shutdown"])
def test_clean_midstream_end(app, account, database, monkeypatch, reason):
    params = sync.cursor(account, 0)
    owner = params["cursor_user_id"]
    app.state.stream_poll_seconds = 60 if reason == "shutdown" else 0.02

    def unavailable(*args):
        raise OperationalError("unavailable", {}, Exception("private DB diagnostic"))

    async def run():
        async with open_stream(app, account[2], params) as stream:
            check_connected(await stream.frame(), owner, 0, 0)
            if reason == "shutdown":
                app.state.stop.set()
            elif reason == "database":
                monkeypatch.setattr(repo, "high_water_mark", unavailable)
            else:
                with psycopg.connect(database["owner"]) as conn:
                    if reason == "inactive":
                        conn.execute("UPDATE siaga.users SET active=false WHERE id=%s", (owner,))
                    else:
                        conn.execute(
                            "UPDATE siaga.users SET last_notification_sequence=1 WHERE id=%s",
                            (owner,),
                        )
            await stream.eof()
        assert app.state.engine.pool.checkedout() == 0
        if reason == "database":
            async with open_stream(app, account[2], params) as retry:
                await retry.expect_error(503, "SERVICE_UNAVAILABLE")

    asyncio.run(run())


def test_uvicorn_live_tcp_stream(settings, account, app, clock):
    sync.publish(app, sync.quakes(1))
    # TestClient owns the fixture app's lifespan. TCP gets an independent app/pool.
    tcp_app = create_app(settings)
    owner = account[1]["user"]["id"]
    headers = {**account[2], "Last-Event-ID": f"{owner}:0"}

    async def run():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
            server = uvicorn.Server(uvicorn.Config(
                tcp_app, host="127.0.0.1", port=port, log_config=None, access_log=False,
                timeout_graceful_shutdown=2,
            ))
            task = asyncio.create_task(server.serve(sockets=[listener]))
            try:
                async with asyncio.timeout(8):
                    while not server.started:
                        if task.done():
                            await task
                            pytest.fail("Uvicorn stopped before accepting connections")
                        await asyncio.sleep(0.01)
                    async with httpx.AsyncClient(
                        base_url=f"http://127.0.0.1:{port}", trust_env=False, timeout=4,
                    ) as client:
                        async with client.stream("GET", STREAM, headers=headers) as response:
                            assert response.status_code == 200
                            content_type = response.headers["content-type"]
                            assert content_type == "text/event-stream; charset=utf-8"
                            assert response.headers["cache-control"] == "no-store"
                            assert response.headers["connection"] == "keep-alive"
                            assert response.headers["x-accel-buffering"] == "no"
                            UUID(response.headers["x-request-id"])
                            lines = response.aiter_lines()
                            connected = [await anext(lines) for _ in range(3)]
                            check_connected(connected, owner, 0, 1)
                            assert await anext(lines) == ""
                            alert = [await anext(lines) for _ in range(3)]
                            assert await anext(lines) == ""
                            history = await client.get(sync.HISTORY, headers=account[2])
                            assert history.status_code == 200
                            check_alert(alert, owner, history.json()["items"][0])
            finally:
                tcp_app.state.stop.set()
                server.should_exit = True
                await asyncio.wait_for(task, 5)

    asyncio.run(run())
