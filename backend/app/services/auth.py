from sqlalchemy.exc import IntegrityError

from app.core.errors import ApiError
from app.core.security import DUMMY_HASH, issue_token, password_hasher
from app.models.user import User
from app.repositories.users import by_email, user_dto
from app.schemas.auth import AuthData


def auth_data(session, user, settings):
    token, expires = issue_token(user.id, settings)
    return AuthData(
        access_token=token, expires_at=expires, expires_in=settings.jwt_ttl_seconds,
        user=user_dto(session, user),
    )


def register(session, body, settings):
    now = settings.domain_now()
    user = User(
        email=body.email,
        display_name=body.display_name,
        password_hash=password_hasher.hash(body.password),
        role="citizen",
        created_at=now,
        updated_at=now,
    )
    session.add(user)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        if getattr(exc.orig, "sqlstate", None) == "23505" and by_email(session, body.email):
            raise ApiError(409, "EMAIL_ALREADY_REGISTERED", "Email sudah terdaftar. Silakan masuk.")
        raise
    session.refresh(user)
    return auth_data(session, user, settings)


def login(session, body, settings):
    user = by_email(session, body.email)
    valid = password_hasher.verify(body.password, user.password_hash if user else DUMMY_HASH)
    if not user or not valid or not user.active:
        raise ApiError(401, "INVALID_CREDENTIALS", "Email atau kata sandi tidak sesuai.")
    return auth_data(session, user, settings)
