from sqlalchemy import text
from sqlmodel import select

from app.models.user import User
from app.schemas.auth import UserDTO


def by_email(session, email):
    return session.exec(select(User).where(User.email == email)).first()


def user_dto(session, user):
    has_zone = session.execute(
        text("SELECT EXISTS (SELECT 1 FROM siaga.alert_zones WHERE user_id = :id)"), {"id": user.id}
    ).scalar_one()
    return UserDTO(
        id=user.id,
        email=user.email,
        display_name=user.display_name,
        role=user.role,
        has_zone=has_zone,
    )
