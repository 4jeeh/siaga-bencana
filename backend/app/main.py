import asyncio
import json
import logging
import re
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.routes import MAX_BODY_BYTES, router
from app.core.config import Settings
from app.core.errors import ApiError, error_response, install_handlers
from app.core.rate_limit import RateLimiter
from app.db.session import make_engine
from app.schemas.events import FeedQuery, MapQuery
from app.schemas.locations import LocationSearchQuery
from app.schemas.notifications import (
    NotificationHistoryQuery,
    NotificationStreamQuery,
    NotificationSyncQuery,
)
from app.schemas.reports import ReportListQuery, SignedPhotoQuery, VerificationQuery
from app.services.bmkg_sync import scheduler
from app.services.locations import LocationService
from app.services.notification_stream import StreamRegistry
from app.services.readiness import StorageProbe, start_storage, stop_storage
from app.services.storage import build_storage_adapter
from app.services.weather import WeatherService

logger = logging.getLogger("siaga")
AUTH_PATHS = {"/api/v1/auth/login": 5, "/api/v1/auth/register": 3}
REPORTS_PATH = "/api/v1/reports"
MODERATION_PATH = re.compile(r"/api/v1/reports/[^/]+/(claim|decision)")
NOTIFICATION_READ_PATH = re.compile(r"/api/v1/me/notifications/[^/]+/read")
VERIFICATIONS_PATH = re.compile(r"/api/v1/reports/[^/]+/verifications")
MEDIA_PATH = re.compile(r"/api/v1/media/reports/[^/]+/photo")
QUERY_FIELDS = {
    ("GET", "/api/v1/locations/search"): LocationSearchQuery.model_fields,
    ("GET", "/api/v1/me/weather"): (),
    ("GET", "/api/v1/me/notifications"): NotificationHistoryQuery.model_fields,
    ("GET", "/api/v1/me/notifications/sync"): NotificationSyncQuery.model_fields,
    ("GET", "/api/v1/me/notifications/stream"): NotificationStreamQuery.model_fields,
    ("GET", "/api/v1/events"): FeedQuery.model_fields,
    ("GET", "/api/v1/map/markers"): MapQuery.model_fields,
    ("GET", REPORTS_PATH): ReportListQuery.model_fields,
}


def allowed_query(method, path):
    if method == "GET":
        if VERIFICATIONS_PATH.fullmatch(path):
            return VerificationQuery.model_fields
        if MEDIA_PATH.fullmatch(path):
            return SignedPhotoQuery.model_fields
    return QUERY_FIELDS.get((method, path), ())


def redact_photo_query(record):
    # Uvicorn passes (client, method, request target, HTTP version, status).
    args = record.args
    if isinstance(args, tuple) and len(args) == 5 and isinstance(args[2], str):
        path, separator, _ = args[2].partition("?")
        if separator and MEDIA_PATH.fullmatch(path):
            record.args = (*args[:2], path, *args[3:])
    return True


def reject_json_constant(value):
    raise ValueError("Non-finite JSON")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Ambiguous JSON field")
        result[key] = value
    return result


def create_app(settings: Settings | None = None):
    settings = settings or Settings()
    logging.getLogger("uvicorn.access").addFilter(redact_photo_query)

    @asynccontextmanager
    async def lifespan(app):
        task = await start_storage(app.state.storage_probe)
        stop = app.state.stop = asyncio.Event()
        worker = (
            asyncio.create_task(scheduler(app.state.engine, settings, stop))
            if settings.bmkg_sync_enabled
            else None
        )
        try:
            yield
        finally:
            stop.set()
            if worker is not None:
                await worker
            await stop_storage(task)
            app.state.engine.dispose()

    app = FastAPI(title="Siaga Bencana", version="0.1.0", lifespan=lifespan, redirect_slashes=False)
    app.state.settings = settings
    app.state.locations = LocationService()
    app.state.weather = WeatherService()
    app.state.engine = make_engine(settings)
    app.state.limiter = RateLimiter()
    app.state.stop = asyncio.Event()
    app.state.stream_registry = StreamRegistry()
    app.state.stream_poll_seconds = 2
    app.state.stream_heartbeat_seconds = 20
    app.state.stream_batch_size = 20
    app.state.storage_probe = StorageProbe(settings)
    app.state.storage = build_storage_adapter(settings)
    app.state.in_flight_uploads = set()
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["GET", "POST", "PUT"],
            allow_headers=["Authorization", "Content-Type", "Accept", "Last-Event-ID"],
            expose_headers=["X-Request-ID", "Retry-After", "Location", "Idempotent-Replay"],
        )

    @app.middleware("http")
    async def protocol(request: Request, call_next):
        request.state.request_id = str(uuid4())
        try:
            path = request.url.path
            if path.startswith("/api/v1/"):
                if (
                    request.method == "GET"
                    and settings.storage_backend != "local"
                    and MEDIA_PATH.fullmatch(path)
                ):
                    raise ApiError(404, "RESOURCE_NOT_FOUND", "Rute media lokal tidak tersedia.")
                keys = list(request.query_params.keys())
                if any(len(request.query_params.getlist(key)) > 1 for key in keys):
                    raise ApiError(400, "MALFORMED_REQUEST", "Parameter query berulang.")
                if set(keys).difference(allowed_query(request.method, path)):
                    raise ApiError(
                        422,
                        "VALIDATION_ERROR",
                        "Parameter tidak dikenal.",
                        {"fields": [{"field": "query", "code": "extra_forbidden"}]},
                    )
                if path in AUTH_PATHS and request.method == "POST":
                    peer = request.client.host if request.client else "unknown"
                    app.state.limiter.check(f"{path}:{peer}", AUTH_PATHS[path])
                json_post = request.method == "POST" and (
                    path in AUTH_PATHS
                    or MODERATION_PATH.fullmatch(path)
                    or NOTIFICATION_READ_PATH.fullmatch(path)
                )
                json_request = json_post or (path == "/api/v1/me/zone" and request.method == "PUT")
                media_type = request.headers.get("content-type", "").partition(";")[0].strip()
                if json_request and media_type.lower() != "application/json":
                    raise ApiError(415, "UNSUPPORTED_MEDIA_TYPE", "Gunakan application/json.")
                if path == REPORTS_PATH and request.method == "POST":
                    if media_type.lower() != "multipart/form-data":
                        raise ApiError(
                            415, "UNSUPPORTED_MEDIA_TYPE", "Gunakan multipart/form-data."
                        )
                # Bound actual bytes including requests without Content-Length.
                chunks = bytearray()
                async for chunk in request.stream():
                    if len(chunks) + len(chunk) > MAX_BODY_BYTES:
                        raise ApiError(
                            413,
                            "REQUEST_TOO_LARGE",
                            "Permintaan terlalu besar.",
                            {"max_bytes": MAX_BODY_BYTES},
                        )
                    chunks.extend(chunk)
                request._body = bytes(chunks)
                if request.method == "GET" and chunks:
                    raise ApiError(400, "MALFORMED_REQUEST", "GET tidak menerima body.")
                if json_request:
                    try:
                        json.loads(
                            chunks,
                            parse_constant=reject_json_constant,
                            object_pairs_hook=unique_object,
                        )
                    except ValueError, UnicodeDecodeError:
                        raise ApiError(400, "MALFORMED_REQUEST", "JSON tidak valid.") from None
            response = await call_next(request)
        except ApiError as exc:
            response = error_response(request, exc)
        except Exception as exc:
            # Do not log exception messages or SQL bind values (passwords / DSNs).
            logger.error(
                "request_id=%s exception_type=%s", request.state.request_id, type(exc).__name__
            )
            response = error_response(
                request,
                ApiError(500, "INTERNAL_ERROR", "Terjadi kesalahan internal. Coba lagi nanti."),
            )
        response.headers["X-Request-ID"] = request.state.request_id
        response.headers["Cache-Control"] = "no-store"
        return response

    install_handlers(app)
    app.include_router(router)
    return app
