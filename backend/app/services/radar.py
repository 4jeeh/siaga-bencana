"""Pure BMKG identity, geometry and priority calculations. Points are (latitude, longitude)."""

import hashlib
import json
import math
import re
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import ROUND_HALF_UP, Context, Decimal, InvalidOperation
from itertools import pairwise
from typing import Literal, TypedDict

EARTH_RADIUS_KM = 6371.0088
RADIUS_TOLERANCE_KM = 0.000001
BOUNDARY_TOLERANCE_DEG = 1e-9
MAX_CAP_VERTICES = 10000

Point = tuple[float, float]
Timestamp = str | datetime


def _utc(value: Timestamp) -> datetime:
    if isinstance(value, str):
        # fromisoformat silently truncates excess fractional digits.
        if re.search(r"[.,][0-9]{7}", value):
            raise ValueError("Timestamp exceeds microsecond precision")
        value = datetime.fromisoformat(value)
    if not isinstance(value, datetime) or value.utcoffset() is None:
        raise ValueError("Expected a timestamp with a timezone")
    try:
        return value.astimezone(UTC)
    except OverflowError as exc:
        raise ValueError("Timestamp outside the UTC datetime range") from exc


def parse_utc_timestamp(value: Timestamp) -> str:
    return _utc(value).isoformat(timespec="microseconds").replace("+00:00", "Z")


def canonical_decimal_coord(value, axis: Literal["latitude", "longitude"]) -> str:
    if axis not in ("latitude", "longitude"):
        raise ValueError("Unknown coordinate axis")
    try:
        number = Decimal(str(value))
    except InvalidOperation as exc:
        raise ValueError("Invalid decimal coordinate") from exc
    limit = 90 if axis == "latitude" else 180
    if not number.is_finite() or not -limit <= number <= limit:
        raise ValueError(f"Invalid {axis}")
    rounded = number.quantize(Decimal("0.000001"), context=Context(prec=16, rounding=ROUND_HALF_UP))
    if rounded == 180:
        return "-180.000000"
    return format(rounded.copy_abs() if rounded.is_zero() else rounded, "f")


def tews_source_key(occurred_at: Timestamp, latitude, longitude) -> str:
    identity = "|".join(
        (
            "TEWS",
            parse_utc_timestamp(occurred_at),
            canonical_decimal_coord(latitude, "latitude"),
            canonical_decimal_coord(longitude, "longitude"),
        )
    )
    return hashlib.sha256(identity.encode("ascii")).hexdigest()


def compute_content_hash(payload_dict: dict) -> str:
    """Hash normalized JSON content, excluding top-level ingestion timestamps."""
    metadata = {"first_seen_at", "last_seen_at", "fetched_at"}
    content = {key: value for key, value in payload_dict.items() if key not in metadata}
    data = json.dumps(
        content, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
    )
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def _finite(value) -> float:
    if isinstance(value, bool):
        raise ValueError("Expected a finite number")
    try:
        number = float(value)
    except (TypeError, OverflowError) as exc:
        raise ValueError("Expected a finite number") from exc
    if not math.isfinite(number):
        raise ValueError("Expected a finite number")
    return number


def _point(lat, lon) -> Point:
    lat, lon = _finite(lat), _finite(lon)
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError("Coordinates outside Earth bounds")
    return lat or 0.0, -180.0 if lon == 180 else lon or 0.0


def _wrap(lon: float) -> float:
    lon = math.remainder(lon, 360)
    return -180.0 if lon == 180 else lon


def haversine_km(lat1, lon1, lat2, lon2) -> float:
    lat1, lon1 = _point(lat1, lon1)
    lat2, lon2 = _point(lat2, lon2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(_wrap(lon2 - lon1))
    cos_product = (
        0.0
        if abs(lat1) == 90 or abs(lat2) == 90
        else math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
    )
    a = math.sin(dlat / 2) ** 2 + cos_product * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(max(0.0, min(1.0, a))))


def is_within_radius(distance_km: float, radius_km: float) -> bool:
    return 0 <= distance_km <= radius_km + RADIUS_TOLERANCE_KM and radius_km >= 0


@dataclass(frozen=True)
class BoundingBox:
    south: float
    north: float
    west: float
    east: float

    @property
    def crosses_antimeridian(self) -> bool:
        return self.west > self.east


def zone_bounding_box(lat, lon, radius_km: float) -> BoundingBox:
    """Conservative candidate bounds. [-180, 180] denotes all longitudes."""
    lat, lon = _point(lat, lon)
    radius = _finite(radius_km)
    if radius < 0:
        raise ValueError("Negative radius")
    angular = (radius + RADIUS_TOLERANCE_KM) / EARTH_RADIUS_KM
    delta = math.degrees(angular) + BOUNDARY_TOLERANCE_DEG
    south, north = max(-90.0, lat - delta), min(90.0, lat + delta)
    if south == -90 or north == 90:
        return BoundingBox(south, north, -180.0, 180.0)
    ratio = math.sin(angular) / math.cos(math.radians(lat))
    width = math.degrees(math.asin(min(1.0, ratio))) + BOUNDARY_TOLERANCE_DEG
    return BoundingBox(south, north, _wrap(lon - width), _wrap(lon + width))


@dataclass(frozen=True)
class Vertex:
    sequence: int
    latitude: float
    longitude: float


@dataclass(frozen=True)
class PolygonAnalysis:
    geometry_valid: bool
    reason: str | None = None
    unwrapped_ring: tuple[Point, ...] = ()
    vertices: tuple[Vertex, ...] = ()
    south: float | None = None
    north: float | None = None
    west: float | None = None
    east: float | None = None
    crosses_antimeridian: bool | None = None
    centroid_latitude: float | None = None
    centroid_longitude: float | None = None


def _unwrap(points: list[Point]) -> tuple[Point, ...]:
    offset = 0
    previous = points[0][1]
    ring = []
    for lat, lon in points:
        if lon - previous > 180:
            offset -= 360
        elif lon - previous < -180:
            offset += 360
        ring.append((lat, lon + offset))
        previous = lon
    return tuple(ring)


def _cross(a: Point, b: Point, c: Point) -> float:
    return (b[1] - a[1]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[1] - a[1])


def _straddles(u: float, v: float) -> bool:
    return u <= 0 <= v or v <= 0 <= u


def _self_intersects(ring: tuple[Point, ...]) -> bool:
    # Sweep by longitude, comparing only segments with overlapping bounding boxes.
    segments = []
    for i, (a, b) in enumerate(pairwise(ring)):
        segments.append((min(a[1], b[1]), max(a[1], b[1]), min(a[0], b[0]), max(a[0], b[0]), i))
    active = []
    for west, east, south, north, i in sorted(segments):
        active = [s for s in active if s[0] >= west]
        a, b = ring[i : i + 2]
        for _, low, high, j in active:
            if high < south or north < low or abs(i - j) in (1, len(ring) - 2):
                continue
            c, d = ring[j : j + 2]
            if _straddles(_cross(a, b, c), _cross(a, b, d)) and _straddles(
                _cross(c, d, a), _cross(c, d, b)
            ):
                return True
        active.append((east, south, north, i))
    return False


def analyze_polygon(ring: Iterable[Point]) -> PolygonAnalysis:
    """Validate one CAP ring, retaining canonical vertices and its continuous longitude branch."""
    points = []
    try:
        for index, raw in enumerate(ring):
            if index >= MAX_CAP_VERTICES:
                return PolygonAnalysis(False, "too_many_vertices")
            if isinstance(raw, (str, bytes, dict)):
                raise ValueError("Expected a coordinate pair")
            point = _point(*raw)
            if not points or point != points[-1]:
                points.append(point)
    except ValueError, TypeError:
        return PolygonAnalysis(False, "invalid_coordinate")
    if len(set(points)) < 3:
        return PolygonAnalysis(False, "too_few_vertices")
    if points[-1] != points[0]:
        points.append(points[0])
    unwrapped = _unwrap(points)
    lats, lons = zip(*unwrapped)
    if max(lons) - min(lons) >= 360 or unwrapped[-1] != unwrapped[0]:
        return PolygonAnalysis(False, "unsupported_polar_wrap")

    # Shift the origin before the shoelace sums to preserve small areas far from (0, 0).
    origin = unwrapped[0]
    edges = list(pairwise(unwrapped))
    weights = [_cross(origin, a, b) for a, b in edges]
    if not any(weights):
        return PolygonAnalysis(False, "degenerate_area")
    if _self_intersects(unwrapped):
        return PolygonAnalysis(False, "self_intersection")
    twice_area = math.fsum(weights)
    if twice_area == 0:
        return PolygonAnalysis(False, "degenerate_area")

    def centroid(axis: int) -> float:
        moment = math.fsum(
            ((a[axis] - origin[axis]) + (b[axis] - origin[axis])) * w
            for (a, b), w in zip(edges, weights, strict=True)
        )
        return origin[axis] + moment / (3 * twice_area)

    # Use the original canonical endpoints so undoing a 360-degree shift cannot
    # round a stored bound inward and exclude the vertex that defined it.
    west = points[lons.index(min(lons))][1]
    east = points[lons.index(max(lons))][1]
    return PolygonAnalysis(
        geometry_valid=True,
        unwrapped_ring=unwrapped,
        vertices=tuple(Vertex(i, *p) for i, p in enumerate(points, 1)),
        south=min(lats),
        north=max(lats),
        west=west,
        east=east,
        crosses_antimeridian=west > east,
        centroid_latitude=centroid(0),
        centroid_longitude=_wrap(centroid(1)),
    )


def _contains(point: Point, ring: tuple[Point, ...]) -> bool:
    y, lon = point
    west = min(p[1] for p in ring)
    east = max(p[1] for p in ring)
    x = lon + 360 * round(((west + east) / 2 - lon) / 360)
    inside = False
    for (ay, ax), (by, bx) in pairwise(ring):
        dx, dy = bx - ax, by - ay
        # Distance to the finite segment, including either endpoint. Work in degrees.
        length = math.hypot(dx, dy)
        if length:
            ux, uy = dx / length, dy / length
            along = max(0.0, min(length, (x - ax) * ux + (y - ay) * uy))
            distance = math.hypot(x - ax - along * ux, y - ay - along * uy)
            if distance <= BOUNDARY_TOLERANCE_DEG + max(math.ulp(x), math.ulp(y)):
                return True
        if (ay > y) != (by > y) and x < ax + (y - ay) / dy * dx:
            inside = not inside
    return inside


class LocationMatch(TypedDict):
    match_method: str
    match_distance_km: float | None
    within_radius: bool | None


def match_cap_areas(
    zone_lat, zone_lon, radius_km, polygons: Iterable[PolygonAnalysis]
) -> LocationMatch:
    zone = _point(zone_lat, zone_lon)
    nearest = math.inf
    for polygon in polygons:
        if not polygon.geometry_valid:
            continue
        if _contains(zone, polygon.unwrapped_ring):
            return LocationMatch(
                match_method="inside_polygon", match_distance_km=0.0, within_radius=True
            )
        nearest = min(
            nearest, haversine_km(*zone, polygon.centroid_latitude, polygon.centroid_longitude)
        )
        for vertex in polygon.vertices[:-1]:
            nearest = min(nearest, haversine_km(*zone, vertex.latitude, vertex.longitude))
    if nearest == math.inf:
        return LocationMatch(match_method="no_geometry", match_distance_km=None, within_radius=None)
    return LocationMatch(
        match_method="near_polygon_sample",
        match_distance_km=nearest,
        within_radius=is_within_radius(nearest, radius_km),
    )


def _optional_utc(value: Timestamp | None) -> datetime | None:
    try:
        return _utc(value)
    except ValueError:
        return None


def _earthquake_age(occurred_at: Timestamp | None, evaluated_at: datetime) -> timedelta | None:
    occurred = _optional_utc(occurred_at)
    if occurred is None:
        return None
    delta = evaluated_at - occurred
    return max(delta, timedelta(0)) if delta >= -timedelta(minutes=5) else None


def earthquake_lifecycle_status(occurred_at: Timestamp | None, evaluated_at: Timestamp) -> str:
    age = _earthquake_age(occurred_at, _utc(evaluated_at))
    if age is None:
        return "invalid_time"
    return "historical" if age > timedelta(days=1) else "current"


def _nonnegative(value) -> float | None:
    try:
        value = _finite(value)
    except ValueError:
        return None
    return value if value >= 0 else None


def _reason(code: str, text: str, **values) -> dict:
    return {"code": code, "text": text, "values": values}


_LABELS = {
    "ordinary": "Biasa",
    "attention": "Perhatian",
    "high": "Prioritas tinggi",
    "unavailable": "Prioritas belum tersedia",
}


def evaluate_earthquake_priority(
    *,
    distance_km: float | None,
    radius_km: float | None,
    magnitude: float | None,
    occurred_at: Timestamp | None,
    evaluated_at: Timestamp,
    zone_version: int,
) -> dict:
    """Use the unrounded Haversine distance. A missing coordinate yields distance_km=None."""
    now = _utc(evaluated_at)
    age = _earthquake_age(occurred_at, now)
    hours = age.total_seconds() / 3600 if age is not None else None
    distance = _nonnegative(distance_km)
    radius = _nonnegative(radius_km) or None  # A zero radius cannot define P.
    mag = _nonnegative(magnitude)
    within = None
    distance_text = "Jarak atau radius belum tersedia"
    if distance is not None and radius is not None:
        within = is_within_radius(distance, radius)
        distance_text = f"{distance:g} km dari titik pantau, radius {radius:g} km"
    reasons = [
        _reason("distance_radius", distance_text, distance_km=distance, radius_km=radius),
        _reason(
            "magnitude",
            "Magnitudo belum tersedia" if mag is None else f"Magnitudo {mag:g}",
            magnitude=mag,
        ),
        _reason(
            "age",
            "Umur belum tersedia" if hours is None else f"Umur informasi {hours:g} jam",
            age_hours=hours,
        ),
    ]
    inputs = {"distance_km": distance, "radius_km": radius, "magnitude": mag, "occurred_at": hours}
    missing = [key for key, value in inputs.items() if value is None]
    score = display = components = None
    label = "unavailable"
    if missing:
        reasons.append(_reason("missing_data", _LABELS[label], fields=missing))
    else:
        p = max(0.0, (radius - distance) / radius)
        m = min(1.0, mag / 10)
        t = max(0.0, (24 - hours) / 24)
        score = 60 * p + 25 * m + 15 * t
        display = str(
            Decimal(str(score)).quantize(
                Decimal("0.1"), context=Context(prec=16, rounding=ROUND_HALF_UP)
            )
        )
        label = "ordinary" if score < 35 else "attention" if score < 65 else "high"
        components = {
            "p": p,
            "m": m,
            "t": t,
            "age_hours": hours,
            "radius_km": radius,
            "magnitude": mag,
        }
    reasons.append(_reason("application_priority", _LABELS[label], priority_label=label))
    return {
        "priority_algo": "eq-priority-v1",
        "priority_score": score,
        "priority_display": display,
        "priority_label": label,
        "priority_reasons": reasons,
        "components": components,
        "match_method": "point_distance",
        "match_distance_km": distance,
        "within_radius": within,
        "evaluated_at": parse_utc_timestamp(now),
        "zone_version": zone_version,
    }


def cap_lifecycle_status(
    *,
    msg_type: str,
    sent: Timestamp,
    effective: Timestamp | None = None,
    expires: Timestamp | None,
    evaluated_at: Timestamp,
    cancelled: bool = False,
    superseded: bool = False,
    lifecycle_complete: bool | None = None,
) -> str:
    """For Updates, lifecycle_complete=True means the ingest worker resolved the references."""
    if cancelled or msg_type == "Cancel":
        return "cancelled"
    if superseded:
        return "superseded"
    if (
        msg_type not in ("Alert", "Update")
        or lifecycle_complete is False
        or (msg_type == "Update" and lifecycle_complete is not True)
    ):
        return "incomplete"
    sent_at = _optional_utc(sent)
    start = sent_at if effective is None else _optional_utc(effective)
    end = _optional_utc(expires)
    if sent_at is None or start is None or end is None or end <= start:
        return "incomplete"
    now = _utc(evaluated_at)
    if now >= end:
        return "expired"
    return "scheduled" if now < start else "active"


def _cap_enum(value: str | None, known: tuple[str, ...]) -> str | None:
    return value if value is None or value in known else "Unknown"


def evaluate_cap_priority(
    *,
    status: str,
    msg_type: str,
    sent: Timestamp,
    expires: Timestamp | None,
    evaluated_at: Timestamp,
    zone_version: int,
    match: LocationMatch,
    area_descriptions: Iterable[str],
    severity: str | None = None,
    urgency: str | None = None,
    certainty: str | None = None,
    effective: Timestamp | None = None,
    cancelled: bool = False,
    superseded: bool = False,
    lifecycle_complete: bool | None = None,
) -> dict:
    now = _utc(evaluated_at)
    lifecycle = cap_lifecycle_status(
        msg_type=msg_type,
        sent=sent,
        effective=effective,
        expires=expires,
        evaluated_at=now,
        cancelled=cancelled,
        superseded=superseded,
        lifecycle_complete=lifecycle_complete,
    )
    severity = _cap_enum(severity, ("Extreme", "Severe", "Moderate", "Minor", "Unknown"))
    urgency = _cap_enum(urgency, ("Immediate", "Expected", "Future", "Past", "Unknown"))
    certainty = _cap_enum(certainty, ("Observed", "Likely", "Possible", "Unlikely", "Unknown"))
    label = "unavailable"
    if status == "Actual" and lifecycle == "active" and match["within_radius"] is True:
        label = {
            "Extreme": "high",
            "Severe": "high",
            "Moderate": "attention",
            "Minor": "information",
        }.get(severity, "unavailable")
    descriptions = list(area_descriptions)
    location_text = {
        "inside_polygon": "Titik pantau di dalam area peringatan",
        "near_polygon_sample": "Jarak perkiraan ke centroid/vertex area peringatan",
        "no_geometry": "Kecocokan lokasi belum tersedia",
    }[match["match_method"]]
    if match["match_method"] == "near_polygon_sample":
        if match["within_radius"]:
            location_text = "Dekat area peringatan — perkiraan centroid/vertex"
        location_text += f" ({match['match_distance_km']:g} km)"
    start = _optional_utc(sent if effective is None else effective)
    end = _optional_utc(expires)
    reasons = [
        _reason(
            "area", ", ".join(descriptions) or "Area belum tersedia", area_descriptions=descriptions
        ),
        _reason("location_match", location_text, **match),
        _reason(
            "severity", f"Tingkat keparahan: {severity or 'belum tersedia'}", severity=severity
        ),
        _reason(
            "urgency_certainty",
            f"{urgency or 'Belum tersedia'} / {certainty or 'belum tersedia'}",
            urgency=urgency,
            certainty=certainty,
        ),
        _reason(
            "validity",
            f"Status peringatan: {lifecycle}",
            lifecycle_status=lifecycle,
            effective=parse_utc_timestamp(start) if start else None,
            expires=parse_utc_timestamp(end) if end else None,
        ),
    ]
    return {
        "priority_algo": "cap-priority-v1",
        "priority_score": None,
        "priority_display": None,
        "priority_label": label,
        "priority_reasons": reasons,
        "components": None,
        **match,
        "evaluated_at": parse_utc_timestamp(now),
        "zone_version": zone_version,
    }
