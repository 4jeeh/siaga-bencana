import json
import logging
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.routes import router
from app.core.config import Settings
from app.core.errors import ApiError, error_response, install_handlers
from app.core.rate_limit import RateLimiter
from app.db.session import make_engine
from app.services.readiness import StorageProbe, start_storage, stop_storage

logger = logging.getLogger("siaga")
AUTH_PATHS = {"/api/v1/auth/login": 5, "/api/v1/auth/register": 3}
MAX_BODY_BYTES = 3145728


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

    @asynccontextmanager
    async def lifespan(app):
        task = await start_storage(app.state.storage_probe)
        try:
            yield
        finally:
            await stop_storage(task)
            app.state.engine.dispose()

    app = FastAPI(title="Siaga Bencana", version="0.1.0", lifespan=lifespan, redirect_slashes=False)
    app.state.settings = settings
    app.state.engine = make_engine(settings)
    app.state.limiter = RateLimiter()
    app.state.storage_probe = StorageProbe(settings)
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["GET", "POST"],
            allow_headers=["Authorization", "Content-Type", "Accept"],
            expose_headers=["X-Request-ID", "Retry-After"],
        )

    @app.middleware("http")
    async def protocol(request: Request, call_next):
        request.state.request_id = str(uuid4())
        try:
            path = request.url.path
            if path.startswith("/api/v1/"):
                keys = list(request.query_params.keys())
                if any(len(request.query_params.getlist(key)) > 1 for key in keys):
                    raise ApiError(400, "MALFORMED_REQUEST", "Parameter query berulang.")
                if keys:
                    raise ApiError(
                        422,
                        "VALIDATION_ERROR",
                        "Parameter tidak dikenal.",
                        {"fields": [{"field": "query", "code": "extra_forbidden"}]},
                    )
                if path in AUTH_PATHS and request.method == "POST":
                    peer = request.client.host if request.client else "unknown"
                    app.state.limiter.check(f"{path}:{peer}", AUTH_PATHS[path])
                    content_type = request.headers.get("content-type", "").split(";")[0].strip()
                    if content_type.lower() != "application/json":
                        raise ApiError(415, "UNSUPPORTED_MEDIA_TYPE", "Gunakan application/json.")
                # Bound actual bytes including requests without Content-Length.
                chunks = bytearray()
                async for chunk in request.stream():
                    chunks.extend(chunk)
                    if len(chunks) > MAX_BODY_BYTES:
                        raise ApiError(
                            413,
                            "REQUEST_TOO_LARGE",
                            "Permintaan terlalu besar.",
                            {"max_bytes": MAX_BODY_BYTES},
                        )
                request._body = bytes(chunks)
                if request.method == "GET" and chunks:
                    raise ApiError(400, "MALFORMED_REQUEST", "GET tidak menerima body.")
                if path in AUTH_PATHS and request.method == "POST":
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
