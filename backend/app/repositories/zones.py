from sqlalchemy import text
from sqlmodel import select

from app.models.alert_zone import AlertZone
from app.schemas.zone import ZoneDTO


def by_user(session, user_id, *, for_update=False):
    statement = select(AlertZone).where(AlertZone.user_id == user_id)
    if for_update:
        # The parent lock also serializes first creation when no zone row exists.
        session.execute(
            text("SELECT id FROM siaga.users WHERE id = :id FOR UPDATE"), {"id": user_id}
        ).scalar_one()
        statement = statement.with_for_update().execution_options(populate_existing=True)
    return session.exec(statement).one_or_none()


def zone_dto(zone):
    return ZoneDTO(
        id=zone.id,
        latitude=zone.latitude,
        longitude=zone.longitude,
        radius_km=zone.radius_km,
        notify_earthquake=zone.notify_earthquake,
        notify_weather=zone.notify_weather,
        zone_version=zone.zone_version,
        alert_eligible_since=zone.alert_eligible_since,
        updated_at=zone.updated_at,
    )
