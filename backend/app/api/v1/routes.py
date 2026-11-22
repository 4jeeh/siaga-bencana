import asyncio
import re
from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Path, Query, Request, Response
from fastapi.responses import StreamingResponse
from python_multipart.multipart import parse_options_header
from sqlmodel import Session
from starlette.datastructures import UploadFile
from starlette.exceptions import HTTPException
from starlette.formparsers import MultiPartException

from app.core.errors import ApiError
from app.core.security import decode_token_claims
from app.db.session import get_session
from app.models.user import User
from app.repositories.users import user_dto
from app.schemas.auth import AuthData, LoginRequest, RegisterRequest, UserDTO
from app.schemas.common import Envelope, StatusData, envelope, response_meta
from app.schemas.events import Detail, Feed, FeedQuery, MapQuery, MarkerFeed
from app.schemas.notifications import (
    NotificationHistoryFeed,
    NotificationHistoryQuery,
    NotificationReadData,
    NotificationReadRequest,
    NotificationStreamQuery,
    NotificationSyncFeed,
    NotificationSyncQuery,
)
from app.schemas.reports import (
    ClaimRequest,
    DecisionRequest,
    ModerationResult,
    PhotoUrlData,
    ReportFeed,
    ReportListQuery,
    ReportPrivate,
    ReportPublic,
    SignedPhotoQuery,
    VerificationFeed,
    VerificationQuery,
)
from app.schemas.zone import ZoneDTO, ZoneRequest
from app.services import auth, events, notification_stream, notifications, reports, zones
from app.services.readiness import database_ready
from app.services.report_payload import CATEGORIES

router = APIRouter(prefix="/api/v1")
SessionDep = Annotated[Session, Depends(get_session)]


def current_user(request: Request, session: SessionDep):
    header = request.headers.get("authorization")
    if not header:
        raise ApiError(401, "AUTH_REQUIRED", "Silakan masuk terlebih dahulu.")
    parts = header.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise ApiError(401, "TOKEN_INVALID", "Sesi tidak valid, masuk kembali.")
    user_id, request.state.token_expires = decode_token_claims(parts[1], request.app.state.settings)
    user = session.get(User, user_id)
    if not user or not user.active:
        raise ApiError(401, "TOKEN_INVALID", "Sesi tidak valid, masuk kembali.")
    request.app.state.limiter.check(f"read:{user.id}", 120)
    return user


UserDep = Annotated[User, Depends(current_user)]
ReportId = Annotated[UUID, Path()]
MAX_BODY_BYTES = 3_145_728
REPORT_FORM_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["client_request_id", "category", "description", "latitude", "longitude"],
    "properties": {
        "client_request_id": {"type": "string", "format": "uuid"},
        "category": {"type": "string", "enum": sorted(CATEGORIES)},
        "description": {"type": "string"},
        "latitude": {"type": "number", "minimum": -90, "maximum": 90},
        "longitude": {"type": "number", "minimum": -180, "maximum": 180},
        "event_id": {"type": "string", "format": "uuid"},
        "photo": {"type": "string", "format": "binary"},
    },
}


def report_writer(request: Request, user: UserDep):
    request.app.state.limiter.check(f"write:{user.id}", 30)
    return user


WriterDep = Annotated[User, Depends(report_writer)]


def moderator(user: WriterDep):
    if user.role != "admin":
        raise ApiError(403, "FORBIDDEN", "Hanya admin dapat meninjau laporan.")
    return user


ModeratorDep = Annotated[User, Depends(moderator)]


async def report_parts(request: Request, user: WriterDep):
    request.app.state.limiter.check(f"submit:{user.id}", 5)
    # python-multipart's finalize() accepts a truncated final part. Without this
    # check, a truncated optional photo could silently become a valid text-only report.
    _, params = parse_options_header(request.headers["content-type"])
    boundary = params.get(b"boundary")
    if not boundary or not re.search(
        rb"(?:^|\r\n)--" + re.escape(boundary) + rb"--[ \t]*(?:\r\n|$)", await request.body()
    ):
        raise ApiError(400, "MALFORMED_REQUEST", "Batas akhir multipart tidak valid.")
    try:
        form = await request.form(max_part_size=MAX_BODY_BYTES)
    except (MultiPartException, HTTPException):
        raise ApiError(400, "MALFORMED_REQUEST", "Data multipart tidak valid.") from None

    try:
        if len(form.multi_items()) != len(form):
            raise ApiError(400, "MALFORMED_REQUEST", "Bagian multipart berulang.")
        missing = set(REPORT_FORM_SCHEMA["required"]) - form.keys()
        unknown = form.keys() - REPORT_FORM_SCHEMA["properties"].keys()
        if missing or unknown:
            raise ApiError(422, "VALIDATION_ERROR", "Kolom laporan tidak sesuai.")
        fields = {key: value for key, value in form.multi_items() if key != "photo"}
        if any(not isinstance(value, str) for value in fields.values()):
            raise ApiError(422, "VALIDATION_ERROR", "Kolom laporan harus berupa teks.")
        photo = form.get("photo")
        if photo is None:
            return fields, None
        if not isinstance(photo, UploadFile):
            raise ApiError(422, "VALIDATION_ERROR", "Foto harus berupa berkas.")
        return fields, (await photo.read(), photo.content_type or "")
    finally:
        await form.close()


def event_evaluation(request: Request, session: SessionDep, user: UserDep):
    return events.evaluation(session, user.id, request.app.state.settings)


EvaluationDep = Annotated[events.Evaluation, Depends(event_evaluation)]


@router.get("/events")
def list_events(
    session: SessionDep, ctx: EvaluationDep, query: Annotated[FeedQuery, Query()]
) -> Feed:
    return events.feed(session, ctx, query)


@router.get("/events/{event_id}")
def event_detail(event_id: UUID, session: SessionDep, ctx: EvaluationDep) -> Detail:
    return events.detail(session, ctx, event_id)


@router.get("/map/markers")
def map_markers(
    session: SessionDep, ctx: EvaluationDep, query: Annotated[MapQuery, Query()]
) -> MarkerFeed:
    return events.markers(session, ctx, query)


@router.get("/health", response_model=Envelope[StatusData])
def health(request: Request):
    return envelope(request, {"status": "ok"})


@router.get("/ready", response_model=Envelope[StatusData])
def ready(request: Request):
    state = request.app.state
    if not state.storage_probe.ready or not database_ready(
        state.engine, state.settings.runtime_db_role
    ):
        raise ApiError(503, "SERVICE_UNAVAILABLE", "Layanan belum siap. Coba lagi sebentar.")
    return envelope(request, {"status": "ready"})


@router.post("/auth/register", status_code=201, response_model=Envelope[AuthData])
def register(request: Request, body: RegisterRequest, session: SessionDep):
    return envelope(request, auth.register(session, body, request.app.state.settings))


@router.post("/auth/login", response_model=Envelope[AuthData])
def login(request: Request, body: LoginRequest, session: SessionDep):
    return envelope(request, auth.login(session, body, request.app.state.settings))


@router.get("/me", response_model=Envelope[UserDTO])
def me(request: Request, session: SessionDep, user: UserDep):
    return envelope(request, user_dto(session, user))


@router.get("/me/zone", response_model=Envelope[ZoneDTO | None])
def get_zone(request: Request, session: SessionDep, user: UserDep):
    return envelope(request, zones.get_zone(session, user.id))


@router.put("/me/zone", response_model=Envelope[ZoneDTO])
def put_zone(request: Request, body: ZoneRequest, session: SessionDep, user: UserDep):
    return envelope(request, zones.replace_zone(session, user.id, body, request.app.state.settings))


@router.get("/me/notifications")
def notification_history(
    request: Request, session: SessionDep, user: UserDep,
    query: Annotated[NotificationHistoryQuery, Query()],
) -> NotificationHistoryFeed:
    return notifications.history(session, user, query, response_meta(request))


@router.get("/me/notifications/sync")
def notification_sync(
    request: Request, session: SessionDep, user: UserDep,
    query: Annotated[NotificationSyncQuery, Query()],
) -> NotificationSyncFeed:
    user_id = user.id
    # Release the auth connection before checking out the dedicated snapshot connection.
    session.close()
    state = request.app.state
    return notifications.sync(state.engine, user_id, query, state.settings, response_meta(request))


def stream_cursor(
    request: Request, session: SessionDep, user: UserDep,
    query: Annotated[NotificationStreamQuery, Query()],
    last_event_ids: Annotated[list[str] | None, Header(alias="Last-Event-ID")] = None,
):
    user_id = user.id
    session.close()
    owner, since = query.cursor(last_event_ids)
    notifications.require_cursor_owner(owner, user_id)
    # Request-scoped cleanup also covers disconnects before the first generator iteration.
    with request.app.state.stream_registry.reserve(user_id):
        yield user_id, since


@router.get(
    "/me/notifications/stream", response_class=StreamingResponse,
    responses={200: {"content": {"text/event-stream": {"schema": {"type": "string"}}}}},
)
async def stream_notifications(
    request: Request, cursor: Annotated[tuple[UUID, int], Depends(stream_cursor, scope="request")],
):
    state = request.app.state
    user_id, since = cursor
    first = await asyncio.to_thread(
        notification_stream.snapshot, state, user_id, since, initial=True
    )
    expires = request.state.token_expires
    if expires <= datetime.now(UTC):
        raise ApiError(401, "TOKEN_EXPIRED", "Sesi berakhir, masuk kembali.")
    if state.stop.is_set():
        raise ApiError(503, "SERVICE_UNAVAILABLE", "Layanan notifikasi sedang berhenti.")
    return StreamingResponse(
        notification_stream.frames(state, user_id, since, expires, first),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-store", "Connection": "keep-alive", "X-Accel-Buffering": "no",
        },
    )


@router.post(
    "/me/notifications/{notification_id}/read", response_model=Envelope[NotificationReadData]
)
def read_notification(
    request: Request, notification_id: UUID, session: SessionDep, user: WriterDep,
    body: NotificationReadRequest,
):
    data = notifications.mark_read(session, user, notification_id, request.app.state.settings)
    return envelope(request, data)


@router.post(
    "/reports", status_code=201, response_model=Envelope[ReportPrivate],
    responses={200: {"model": Envelope[ReportPrivate], "description": "Idempotent replay"}},
    openapi_extra={
        "requestBody": {
            "required": True,
            "content": {"multipart/form-data": {"schema": REPORT_FORM_SCHEMA}},
        }
    },
)
def submit_report(
    request: Request, response: Response, session: SessionDep, user: WriterDep,
    parts: Annotated[tuple, Depends(report_parts)],
):
    data, replay = reports.submit(request.app.state, session, user, *parts)
    response.status_code = 200 if replay else 201
    response.headers["Idempotent-Replay"] = "true" if replay else "false"
    if not replay:
        response.headers["Location"] = f"/api/v1/reports/{data.id}"
    return envelope(request, data)


@router.get("/reports")
def list_reports(
    request: Request, session: SessionDep, user: UserDep, query: Annotated[ReportListQuery, Query()]
) -> ReportFeed:
    return reports.feed(session, user, query, response_meta(request))


@router.get("/reports/{report_id}", response_model=Envelope[ReportPrivate | ReportPublic])
def report_detail(request: Request, report_id: ReportId, session: SessionDep, user: UserDep):
    return envelope(request, reports.detail(session, user, report_id))


@router.get("/reports/{report_id}/photo-url", response_model=Envelope[PhotoUrlData])
def report_photo_url(request: Request, report_id: ReportId, session: SessionDep, user: UserDep):
    return envelope(request, reports.signed_url(request, session, user, report_id))


@router.get(
    "/media/reports/{report_id}/photo",
    response_class=Response,
    responses={
        200: {"content": {"image/jpeg": {"schema": {"type": "string", "format": "binary"}}}}
    },
)
def report_photo(
    request: Request, report_id: ReportId, session: SessionDep,
    query: Annotated[SignedPhotoQuery, Query()],
):
    data = reports.local_photo(
        request.app.state, session, report_id, query.expires, query.signature
    )
    return Response(content=data, media_type="image/jpeg", headers={
        "Content-Disposition": "inline", "X-Content-Type-Options": "nosniff",
        "Cache-Control": "no-store",
    })


@router.post("/reports/{report_id}/claim", response_model=Envelope[ModerationResult])
def claim_report(
    request: Request, report_id: ReportId, session: SessionDep, user: ModeratorDep,
    body: ClaimRequest,
):
    result = reports.moderate(session, user, report_id, body, request.app.state.settings)
    return envelope(request, result)


@router.post("/reports/{report_id}/decision", response_model=Envelope[ModerationResult])
def decide_report(
    request: Request, report_id: ReportId, session: SessionDep, user: ModeratorDep,
    body: DecisionRequest,
):
    result = reports.moderate(session, user, report_id, body, request.app.state.settings)
    return envelope(request, result)


@router.get("/reports/{report_id}/verifications")
def report_verifications(
    request: Request, report_id: ReportId, session: SessionDep, user: UserDep,
    query: Annotated[VerificationQuery, Query()],
) -> VerificationFeed:
    return reports.verifications(session, user, report_id, query, response_meta(request))
