from collections import defaultdict
from datetime import timedelta

from sqlalchemy import and_, or_
from sqlalchemy.orm import defer
from sqlmodel import select

from app.models.citizen_report import CitizenReport
from app.models.disaster_event import (
    AreaPolygon,
    DisasterEvent,
    EventArea,
    EventReference,
    PolygonVertex,
)
from app.schemas.events import Area, Polygon, Vertex


def point_in_box(model, box):
    lat, lon = model.latitude, model.longitude
    longitude = (
        or_(lon >= box.west, lon <= box.east)
        if box.crosses_antimeridian
        else lon.between(box.west, box.east)
    )
    return and_(lat.between(box.south, box.north), longitude)


def polygon_in_box(box):
    p = AreaPolygon
    # Two wrapped intervals both contain the dateline. Otherwise intersect the
    # ordinary intervals on either side of it, including their boundaries.
    if box.crosses_antimeridian:
        longitude = or_(p.crosses_antimeridian, p.east >= box.west, p.west <= box.east)
    else:
        longitude = or_(
            and_(p.crosses_antimeridian, or_(p.east >= box.west, p.west <= box.east)),
            and_(~p.crosses_antimeridian, p.east >= box.west, p.west <= box.east),
        )
    return (
        select(EventArea.id)
        .join(p, p.area_id == EventArea.id)
        .where(
            EventArea.event_id == DisasterEvent.id,
            p.geometry_valid,
            p.north >= box.south,
            p.south <= box.north,
            longitude,
        )
        .exists()
    )


def event_candidates(now, category, active_only, radius_box=None, viewport=None):
    e = DisasterEvent
    quake = and_(e.category == "earthquake", e.occurred_at >= now - timedelta(days=7))
    weather = and_(
        e.category == "extreme_weather", e.source == "BMKG_NOWCAST", e.status == "Actual"
    )
    active = and_(
        e.cancelled_at.is_(None),
        e.superseded_at.is_(None),
        e.lifecycle_complete,
        e.msg_type.in_(("Alert", "Update")),
        e.effective <= now,
        e.expires > now,
    )
    if active_only:
        weather = and_(weather, active)
    if radius_box:
        quake = and_(quake, point_in_box(e, radius_box))
        weather = and_(weather, polygon_in_box(radius_box))
    scopes = {"earthquake": quake, "extreme_weather": weather}
    scope = or_(quake, weather) if category is None else scopes.get(category, False)
    statement = select(e).options(defer(e.provenance), defer(e.content_hash)).where(scope)
    if viewport:
        statement = statement.where(point_in_box(e, viewport))
    if category == "extreme_weather" and not active_only:
        statement = statement.order_by(active.is_(True).desc())
    return statement.order_by(e.occurred_at.desc(), e.id.desc())


def report_candidates(category, radius_box, viewport):
    report = CitizenReport
    query = select(report).where(report.status == "verified")
    if category:
        query = query.where(report.category == category)
    for box in (radius_box, viewport):
        if box:
            query = query.where(point_in_box(report, box))
    return query


def event_areas(session, event_ids):
    """Load each level once per batch, retaining empty areas and invalid polygons."""
    grouped = defaultdict(list)
    if not event_ids:
        return grouped
    areas = session.exec(
        select(EventArea).where(EventArea.event_id.in_(event_ids)).order_by(EventArea.position)
    ).all()
    if not areas:
        return grouped
    polygons = session.exec(
        select(AreaPolygon)
        .where(AreaPolygon.area_id.in_([a.id for a in areas]))
        .order_by(AreaPolygon.position)
    ).all()
    valid_ids = [p.id for p in polygons if p.geometry_valid]
    vertices = defaultdict(list)
    if valid_ids:
        rows = session.exec(
            select(PolygonVertex)
            .where(PolygonVertex.polygon_id.in_(valid_ids))
            .order_by(PolygonVertex.sequence)
        )
        for row in rows:
            vertices[row.polygon_id].append(Vertex.model_validate(row, from_attributes=True))
    by_area = defaultdict(list)
    for p in polygons:
        by_area[p.area_id].append(Polygon(**p.model_dump(), vertices=vertices[p.id]))
    for a in areas:
        grouped[a.event_id].append(Area(**a.model_dump(), polygons=by_area[a.id]))
    return grouped


def references(session, event_id):
    return session.exec(
        select(EventReference)
        .where(EventReference.event_id == event_id)
        .order_by(EventReference.referenced_source_key, EventReference.id)
    ).all()
