from dataclasses import dataclass
from datetime import UTC, datetime
from heapq import nlargest, nsmallest
from itertools import batched, chain, islice

from app.core.errors import ApiError
from app.models.alert_zone import AlertZone
from app.models.disaster_event import DisasterEvent
from app.repositories import events as repo
from app.repositories.zones import by_user
from app.schemas.events import (
    CapSummary,
    Earthquake,
    EventDetail,
    EventMeta,
    EventSummary,
    Marker,
    Reference,
    Weather,
)
from app.services import radar
from app.services.bmkg_sync import source_freshness


@dataclass
class Evaluation:
    zone: AlertZone
    meta: EventMeta

    @property
    def now(self):
        return self.meta.server_time

    def radius_box(self):
        return radar.zone_bounding_box(self.zone.latitude, self.zone.longitude, self.zone.radius_km)


def evaluation(session, user_id, settings):
    zone = by_user(session, user_id)
    if zone is None:
        raise ApiError(
            409, "ZONE_REQUIRED", "Atur zona pantau terlebih dahulu.", {"action": "setup_zone"}
        )
    now = settings.domain_now()
    simulated = settings.app_mode == "simulation"
    return Evaluation(
        zone,
        EventMeta(
            server_time=now,
            mode=settings.app_mode,
            is_simulated=simulated,
            zone_version=zone.zone_version,
            sources=source_freshness(session, now if simulated else datetime.now(UTC)),
        ),
    )


def summary(event, areas, ctx):
    zone = ctx.zone
    common = dict(evaluated_at=ctx.now, zone_version=zone.zone_version)
    cap = None
    if event.category == "earthquake":
        distance = radar.haversine_km(
            zone.latitude, zone.longitude, event.latitude, event.longitude
        )
        priority = radar.evaluate_earthquake_priority(
            distance_km=distance,
            radius_km=zone.radius_km,
            magnitude=event.magnitude,
            occurred_at=event.occurred_at,
            **common,
        )
        status = radar.earthquake_lifecycle_status(event.occurred_at, ctx.now)
    else:
        polygons = (
            radar.PolygonAnalysis.from_stored_ring(
                p.vertices, p.centroid_latitude, p.centroid_longitude
            )
            for a in areas
            for p in a.polygons
            if p.geometry_valid
        )
        match = radar.match_cap_areas(zone.latitude, zone.longitude, zone.radius_km, polygons)
        cap = CapSummary(
            severity=event.severity,
            urgency=event.urgency,
            certainty=event.certainty,
            effective=event.effective or event.sent,
            expires=event.expires,
            area_descriptions=[a.area_description for a in areas],
        )
        lifecycle = dict(
            msg_type=event.msg_type,
            sent=event.sent,
            cancelled=event.cancelled_at is not None,
            superseded=event.superseded_at is not None,
            lifecycle_complete=event.lifecycle_complete,
            effective=cap.effective,
            expires=cap.expires,
            evaluated_at=ctx.now,
        )
        status = radar.cap_lifecycle_status(**lifecycle)
        priority = radar.evaluate_cap_priority(
            status=event.status,
            match=match,
            severity=cap.severity,
            urgency=cap.urgency,
            certainty=cap.certainty,
            area_descriptions=cap.area_descriptions,
            zone_version=zone.zone_version,
            **lifecycle,
        )
    return EventSummary(
        id=event.id,
        source=event.source,
        category=event.category,
        title=event.title,
        occurred_at=event.occurred_at,
        latitude=event.latitude,
        longitude=event.longitude,
        is_simulated=event.is_simulated,
        content_version=event.content_version,
        lifecycle_status=status,
        priority=priority,
        cap=cap,
    )


def _summary_rows(session, statement, ctx, radius_only):
    rows = session.exec(statement.execution_options(yield_per=64))
    try:
        for batch in batched(rows, 64):
            areas = repo.event_areas(
                session, [e.id for e in batch if e.category == "extreme_weather"]
            )
            for event in batch:
                item = summary(event, areas[event.id], ctx)
                if not radius_only or item.priority.within_radius:
                    yield event, item
    finally:
        rows.close()


def summaries(session, statement, ctx, radius_only):
    for _, item in _summary_rows(session, statement, ctx, radius_only):
        yield item


def invalid_query(field):
    return ApiError(
        422,
        "VALIDATION_ERROR",
        "Periksa kembali parameter query.",
        {"fields": [{"field": f"query.{field}", "code": "invalid_value"}]},
    )


def feed(session, ctx, query):
    if query.sort == "priority" and query.category != "earthquake":
        raise invalid_query("sort")
    if query.weather_status == "all" and query.radius_only:
        raise invalid_query("weather_status")
    statement = repo.event_candidates(
        ctx.now,
        query.category,
        query.weather_status == "active",
        ctx.radius_box() if query.radius_only else None,
    )
    offset = query.offset
    if query.sort == "recent" and not query.radius_only:
        statement = statement.offset(min(offset, 2**63 - 1)).limit(query.limit + 1)
        offset = 0
    candidates = summaries(session, statement, ctx, query.radius_only)
    if query.sort == "priority":
        # The candidate query has already ordered time and UUID descending.
        candidates = nlargest(
            offset + query.limit + 1,
            candidates,
            key=lambda e: (
                e.priority.priority_score is not None,
                e.priority.priority_score,
                e.occurred_at,
                e.id,
            ),
        )
    page = list(islice((e for i, e in enumerate(candidates) if i >= offset), query.limit + 1))
    more = len(page) > query.limit
    return dict(
        items=page[: query.limit],
        page=dict(
            limit=query.limit,
            offset=query.offset,
            next_offset=query.offset + query.limit if more else None,
            has_more=more,
        ),
        meta=ctx.meta,
    )


def detail(session, ctx, event_id):
    e = session.get(DisasterEvent, event_id)
    if e is None or (e.category == "extreme_weather" and e.status != "Actual"):
        raise ApiError(404, "RESOURCE_NOT_FOUND", "Informasi bencana tidak ditemukan.")
    weather = e.category == "extreme_weather"
    areas = repo.event_areas(session, [e.id])[e.id] if weather else []
    data = EventDetail(
        **summary(e, areas, ctx).model_dump(),
        source_url=e.source_url,
        first_seen_at=e.first_seen_at,
        last_seen_at=e.last_seen_at,
        earthquake=None if weather else Earthquake.model_validate(e, from_attributes=True),
        weather=Weather.model_validate(e, from_attributes=True) if weather else None,
        areas=areas,
        references=[
            Reference.model_validate(r, from_attributes=True)
            for r in repo.references(session, e.id)
        ]
        if weather
        else [],
    )
    return dict(data=data, meta=ctx.meta)


def parse_bbox(value):
    if value is None:
        return None
    try:
        west, south, east, north = map(float, value.split(","))
        if -180 <= west <= 180 and -180 <= east <= 180 and -90 <= south <= north <= 90:
            return radar.BoundingBox(south, north, west, east)
    except ValueError:
        pass
    raise invalid_query("bbox")


def official_markers(session, ctx, query, radius_box, viewport):
    statement = repo.event_candidates(ctx.now, query.category, True, radius_box, viewport)
    for event, item in _summary_rows(session, statement, ctx, query.radius_only):
        p = item.priority
        if item.latitude is not None and p.match_distance_km is not None:
            yield (
                item.occurred_at,
                Marker(
                    id=item.id,
                    kind="event",
                    magnitude=event.magnitude if item.category == "earthquake" else None,
                    depth_km=event.depth_km if item.category == "earthquake" else None,
                    potential=event.potential if item.category == "earthquake" else None,
                    source=item.source,
                    category=item.category,
                    title=item.title,
                    latitude=item.latitude,
                    longitude=item.longitude,
                    is_simulated=item.is_simulated,
                    match_method=p.match_method,
                    match_distance_km=p.match_distance_km,
                    priority_label=p.priority_label,
                ),
            )


def report_markers(session, ctx, query, radius_box, viewport):
    if not query.include_reports:
        return
    statement = repo.report_candidates(query.category, radius_box, viewport)
    zone = ctx.zone
    for row in session.exec(statement.execution_options(yield_per=100)):
        distance = radar.haversine_km(zone.latitude, zone.longitude, row.latitude, row.longitude)
        if not query.radius_only or radar.is_within_radius(distance, zone.radius_km):
            yield (
                row.created_at,
                Marker(
                    id=row.id,
                    kind="report",
                    source="CITIZEN",
                    category=row.category,
                    title=row.description,
                    latitude=row.latitude,
                    longitude=row.longitude,
                    match_method="point_distance",
                    match_distance_km=distance,
                    priority_label=None,
                    is_simulated=row.is_simulated,
                ),
            )


def markers(session, ctx, query):
    viewport = parse_bbox(query.bbox)
    box = ctx.radius_box() if query.radius_only else None
    rows = chain(
        official_markers(session, ctx, query, box, viewport),
        report_markers(session, ctx, query, box, viewport),
    )
    nearest = nsmallest(
        101, rows, key=lambda row: (row[1].match_distance_km, ctx.now - row[0], -row[1].id.int)
    )
    return dict(
        items=[marker for _, marker in nearest[:100]],
        truncated=len(nearest) > 100,
        cap=100,
        meta=ctx.meta,
    )
