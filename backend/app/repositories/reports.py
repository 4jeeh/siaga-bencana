from sqlalchemy import func, tuple_
from sqlmodel import select

from app.models.citizen_report import CitizenReport, ReportVerification
from app.repositories.events import point_in_box
from app.schemas.events import Page
from app.services.radar import EARTH_RADIUS_KM, RADIUS_TOLERANCE_KM, zone_bounding_box


def by_request(session, reporter_id, request_id):
    return session.exec(
        select(CitizenReport).where(
            CitizenReport.reporter_id == reporter_id, CitizenReport.client_request_id == request_id
        )
    ).one_or_none()


def locked_report(session, report_id):
    return session.exec(
        select(CitizenReport)
        .where(CitizenReport.id == report_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    ).one_or_none()


def latest_reasons(session, versions):
    # Match the version of each report as read, even if another transaction has since
    # appended an audit entry. The unique (report_id, resulting_version) index covers this.
    if not versions:
        return {}
    v = ReportVerification
    statement = select(v.report_id, v.reason).where(
        tuple_(v.report_id, v.resulting_version).in_(versions)
    )
    return dict(session.exec(statement).all())


def _nearby(zone):
    r = CitizenReport
    box = zone_bounding_box(zone.latitude, zone.longitude, zone.radius_km)
    # SQL equivalent of radar.haversine_km / is_within_radius, before LIMIT/OFFSET.
    # Squared sines are periodic across the dateline. Clamp rounding at the antipodes.
    lat_term = func.sin(func.radians(r.latitude - zone.latitude) / 2)
    lon_term = func.sin(func.radians(r.longitude - zone.longitude) / 2)
    cos_product = func.cos(func.radians(zone.latitude)) * func.cos(func.radians(r.latitude))
    a = lat_term * lat_term + cos_product * lon_term * lon_term
    distance = 2 * EARTH_RADIUS_KM * func.asin(func.sqrt(func.least(1.0, func.greatest(0.0, a))))
    return point_in_box(r, box), distance <= zone.radius_km + RADIUS_TOLERANCE_KM


def _page(session, statement, query):
    # PostgreSQL OFFSET is a bigint. Any larger offset is necessarily an empty page.
    rows = []
    if query.offset <= 2**63 - 1:
        rows = session.exec(statement.limit(query.limit + 1).offset(query.offset)).all()
    more = len(rows) > query.limit
    return rows[:query.limit], Page(
        limit=query.limit,
        offset=query.offset,
        has_more=more,
        next_offset=query.offset + query.limit if more else None,
    )


def report_page(session, user_id, zone, query):
    r = CitizenReport
    stmt = select(r)
    if query.scope == "review":
        stmt = stmt.where(r.status.in_(("pending", "in_review"))).order_by(r.created_at, r.id)
    else:
        stmt = stmt.order_by(r.created_at.desc(), r.id.desc())
        if query.scope == "mine":
            stmt = stmt.where(r.reporter_id == user_id)
        else:
            stmt = stmt.where(r.status == "verified")
            if query.scope == "nearby":
                stmt = stmt.where(*_nearby(zone))
    if query.category is not None:
        stmt = stmt.where(r.category == query.category)
    if query.status is not None:
        stmt = stmt.where(r.status == query.status)
    if query.event_id is not None:
        stmt = stmt.where(r.event_id == query.event_id)
    return _page(session, stmt, query)


def verification_page(session, report_id, query):
    v = ReportVerification
    stmt = select(v).where(v.report_id == report_id).order_by(v.resulting_version, v.id)
    return _page(session, stmt, query)
