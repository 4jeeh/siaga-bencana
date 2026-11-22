from sqlmodel import select

from app.models.alert_zone import AlertZone
from app.models.user import User
from app.repositories.zones import by_user, zone_dto


def get_zone(session, user_id):
    zone = by_user(session, user_id)
    return zone_dto(zone) if zone is not None else None


def replace_zone(session, user_id, body, settings):
    # Authentication has already started this session's transaction.
    try:
        # Serialize even the first zone creation, in the same lock order as notify().
        session.exec(select(User.id).where(User.id == user_id).with_for_update()).one()
        zone = by_user(session, user_id, for_update=True)
        values = body.model_dump()
        if zone is None:
            now = settings.domain_now()
            zone = AlertZone(
                user_id=user_id,
                **values,
                zone_version=1,
                created_at=now,
                updated_at=now,
                alert_eligible_since=now,
            )
            session.add(zone)
        elif any(getattr(zone, field) != value for field, value in values.items()):
            now = settings.domain_now()
            for field, value in values.items():
                setattr(zone, field, value)
            zone.zone_version += 1
            zone.alert_eligible_since = now
            zone.updated_at = now
        session.flush()
        # Copy while locked; a post-commit refresh could read a subsequent PUT.
        snapshot = zone_dto(zone)
        session.commit()
        return snapshot
    except Exception:
        session.rollback()
        raise
