from typing import Annotated

from fastapi import APIRouter, Depends, Request
from sqlmodel import Session

from app.core.errors import ApiError
from app.core.security import decode_token
from app.db.session import get_session
from app.models.user import User
from app.repositories.users import user_dto
from app.schemas.auth import AuthData, LoginRequest, RegisterRequest, UserDTO
from app.schemas.common import Envelope, StatusData, envelope
from app.schemas.zone import ZoneDTO, ZoneRequest
from app.services import auth, zones
from app.services.readiness import database_ready

router = APIRouter(prefix="/api/v1")
SessionDep = Annotated[Session, Depends(get_session)]


def current_user(request: Request, session: SessionDep):
    header = request.headers.get("authorization")
    if not header:
        raise ApiError(401, "AUTH_REQUIRED", "Silakan masuk terlebih dahulu.")
    parts = header.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise ApiError(401, "TOKEN_INVALID", "Sesi tidak valid, masuk kembali.")
    user_id = decode_token(parts[1], request.app.state.settings)
    user = session.get(User, user_id)
    if not user or not user.active:
        raise ApiError(401, "TOKEN_INVALID", "Sesi tidak valid, masuk kembali.")
    request.app.state.limiter.check(f"read:{user.id}", 120)
    return user


UserDep = Annotated[User, Depends(current_user)]


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
    return envelope(
        request, zones.replace_zone(session, user.id, body, request.app.state.settings)
    )
