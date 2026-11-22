"""Relational event merge, lifecycle resolution and per-user notification snapshots."""

from dataclasses import asdict
from datetime import datetime

from sqlmodel import select

from app.models.alert_zone import AlertZone
from app.models.disaster_event import (
    AreaPolygon,
    DisasterEvent,
    EventArea,
    EventReference,
    PolygonVertex,
)
from app.models.notification_log import NotificationLog
from app.models.user import User
from app.services import radar
from app.services.bmkg_parser import NOWCAST, TEWS


def save_areas(session, event, areas):
    existing = set(session.exec(select(EventArea.position).where(EventArea.event_id == event.id)))
    for pos, (description, polygons) in enumerate(areas, 1):
        if pos in existing:
            continue
        area = EventArea(event_id=event.id, position=pos, area_description=description)
        session.add(area)
        session.flush()
        for index, analysis in enumerate(polygons, 1):
            polygon = AreaPolygon(
                area_id=area.id,
                position=index,
                geometry_valid=analysis.geometry_valid,
                invalid_reason=analysis.reason,
                centroid_latitude=analysis.centroid_latitude,
                centroid_longitude=analysis.centroid_longitude,
                south=analysis.south,
                north=analysis.north,
                west=analysis.west,
                east=analysis.east,
                crosses_antimeridian=analysis.crosses_antimeridian,
            )
            session.add(polygon)
            session.flush()
            session.add_all(
                [PolygonVertex(polygon_id=polygon.id, **asdict(v)) for v in analysis.vertices]
            )


def save_event(session, record, now, simulated):
    fields = record.fields.copy()
    event = session.exec(
        select(DisasterEvent).where(
            DisasterEvent.source == fields["source"],
            DisasterEvent.source_key == fields["source_key"],
        )
    ).one_or_none()
    new = event is None
    if fields["source"] == TEWS:
        if event:
            for key, value in fields.items():
                if value is None:
                    fields[key] = getattr(event, key)
        fields["title"] = (fields["region"] or "Gempa bumi")[:500]
    payload = {
        k: radar.parse_utc_timestamp(v) if isinstance(v, datetime) else v
        for k, v in fields.items()
        if k != "source_url"
    }
    payload["areas"] = [(desc, [asdict(p) for p in polygons]) for desc, polygons in record.areas]
    payload["references"] = [(s, k, radar.parse_utc_timestamp(t)) for s, k, t in record.references]
    payload["references_valid"] = record.references_valid
    digest = radar.compute_content_hash(payload)
    changed = new or event.content_hash != digest
    if new:
        event = DisasterEvent(
            **fields, first_seen_at=now, content_hash=digest, is_simulated=simulated
        )
        session.add(event)
    elif changed:
        for key, value in fields.items():
            setattr(event, key, value)
        event.content_hash = digest
        event.content_version += 1
    event.provenance = record.provenance
    event.last_seen_at = now
    if event.source == NOWCAST:
        event.lifecycle_complete = bool(
            event.expires and event.expires > event.effective and event.msg_type == "Alert"
        )
    session.flush()
    if changed and record.areas:
        save_areas(session, event, record.areas)
    return event, new, changed


def resolve_references(session, event, references, valid, now):
    if event.msg_type not in ("Update", "Cancel"):
        return
    resolved = bool(references) and valid
    for sender, key, sent in references:
        target = session.exec(
            select(DisasterEvent).where(
                DisasterEvent.source == NOWCAST,
                DisasterEvent.source_key == key,
                DisasterEvent.sender == sender,
                DisasterEvent.sent == sent,
                DisasterEvent.id != event.id,
            )
        ).one_or_none()
        ref = session.exec(
            select(EventReference).where(
                EventReference.event_id == event.id,
                EventReference.referenced_sender == sender,
                EventReference.referenced_source_key == key,
                EventReference.referenced_sent == sent,
            )
        ).one_or_none()
        if ref is None:
            ref = EventReference(
                event_id=event.id,
                referenced_sender=sender,
                referenced_source_key=key,
                referenced_sent=sent,
            )
            session.add(ref)
        ref.relation_type = event.msg_type
        ref.referenced_event_id = target.id if target else None
        if target is None:
            resolved = False
        elif event.status == target.status:
            if event.msg_type == "Update":
                target.superseded_at = target.superseded_at or now
            else:
                target.cancelled_at = target.cancelled_at or now
        else:
            resolved = False
    event.lifecycle_complete = bool(resolved and event.expires and event.expires > event.effective)
    # Only the current CAP revision may make a previously unseen target inactive.
    provenance = dict(event.provenance)
    provenance.pop("pending_references", None)
    if not resolved and references:
        provenance["pending_references"] = {
            "valid": valid,
            "triples": [(s, k, radar.parse_utc_timestamp(t)) for s, k, t in references],
        }
    event.provenance = provenance


def settle_lifecycle(session, pending, now):
    for event, record in pending:
        resolve_references(session, event, record.references, record.references_valid, now)
    keys = [event.source_key for event, _ in pending if event.source == NOWCAST]
    if not keys:
        return
    parents = session.exec(
        select(DisasterEvent)
        .join(EventReference, EventReference.event_id == DisasterEvent.id)
        .where(
            EventReference.referenced_event_id.is_(None),
            EventReference.referenced_source_key.in_(keys),
        )
        .distinct()
    ).all()
    for parent in parents:
        waiting = parent.provenance.get("pending_references")
        if waiting:
            triples = [(s, k, datetime.fromisoformat(t)) for s, k, t in waiting["triples"]]
            resolve_references(session, parent, triples, waiting["valid"], now)


def eligible_priority(event, record, zone, now):
    source_time = event.sent if event.source == NOWCAST else event.occurred_at
    if event.first_seen_at <= zone.alert_eligible_since or source_time < zone.alert_eligible_since:
        return None
    common = dict(evaluated_at=now, zone_version=zone.zone_version)
    if event.source == TEWS:
        if (
            not zone.notify_earthquake
            or radar.earthquake_lifecycle_status(event.occurred_at, now) != "current"
        ):
            return None
        distance = radar.haversine_km(
            event.latitude, event.longitude, zone.latitude, zone.longitude
        )
        if not radar.is_within_radius(distance, zone.radius_km):
            return None
        return radar.evaluate_earthquake_priority(
            distance_km=distance,
            radius_km=zone.radius_km,
            magnitude=event.magnitude,
            occurred_at=event.occurred_at,
            **common,
        )
    lifecycle = dict(
        msg_type=event.msg_type,
        sent=event.sent,
        effective=event.effective,
        expires=event.expires,
        lifecycle_complete=event.lifecycle_complete,
        cancelled=event.cancelled_at is not None,
        superseded=event.superseded_at is not None,
    )
    if (
        not zone.notify_weather
        or event.status != "Actual"
        or radar.cap_lifecycle_status(evaluated_at=now, **lifecycle) != "active"
    ):
        return None
    match = radar.match_cap_areas(
        zone.latitude,
        zone.longitude,
        zone.radius_km,
        (p for _, polygons in record.areas for p in polygons),
    )
    if not match["within_radius"]:
        return None
    return radar.evaluate_cap_priority(
        status=event.status,
        match=match,
        area_descriptions=[desc for desc, _ in record.areas],
        severity=event.severity,
        urgency=event.urgency,
        certainty=event.certainty,
        **lifecycle,
        **common,
    )


def notify(session, new_events, now):
    if not new_events:
        return
    new_events = sorted(new_events, key=lambda item: (item[0].occurred_at, item[0].id))
    users = session.exec(
        select(User)
        .join(AlertZone, AlertZone.user_id == User.id)
        .where(User.active.is_(True))
        .order_by(User.id)
        .with_for_update(of=User)
        .execution_options(populate_existing=True)
    ).all()
    by_id = {user.id: user for user in users}
    zones = session.exec(
        select(AlertZone)
        .where(AlertZone.user_id.in_(by_id))
        .order_by(AlertZone.user_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    ).all()
    for zone in zones:
        user = by_id[zone.user_id]
        for event, record in new_events:
            priority = eligible_priority(event, record, zone, now)
            if priority is None:
                continue
            existing = session.exec(
                select(NotificationLog.id).where(
                    NotificationLog.user_id == user.id,
                    NotificationLog.event_id == event.id,
                    NotificationLog.kind == "official_new",
                )
            ).first()
            if existing is not None:
                continue
            user.last_notification_sequence += 1
            session.add(
                NotificationLog(
                    user_id=user.id,
                    event_id=event.id,
                    sequence=user.last_notification_sequence,
                    zone_version=zone.zone_version,
                    created_at=now,
                    evaluated_at=now,
                    is_simulated=event.is_simulated,
                    priority_components=priority["components"],
                    **{
                        key: priority[key]
                        for key in (
                            "priority_algo",
                            "priority_label",
                            "priority_score",
                            "priority_reasons",
                            "match_method",
                            "match_distance_km",
                        )
                    },
                )
            )
