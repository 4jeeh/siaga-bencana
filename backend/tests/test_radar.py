import hashlib
import math
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest

from app.services.radar import (
    BOUNDARY_TOLERANCE_DEG,
    EARTH_RADIUS_KM,
    MAX_CAP_VERTICES,
    RADIUS_TOLERANCE_KM,
    analyze_polygon,
    canonical_decimal_coord,
    cap_lifecycle_status,
    compute_content_hash,
    earthquake_lifecycle_status,
    evaluate_cap_priority,
    evaluate_earthquake_priority,
    haversine_km,
    is_within_radius,
    match_cap_areas,
    parse_utc_timestamp,
    tews_source_key,
    zone_bounding_box,
)


@pytest.fixture
def now():
    return datetime(2026, 11, 16, 3, tzinfo=UTC)


def test_tews_source_identity_is_exact():
    expected = hashlib.sha256(b"TEWS|2026-11-16T03:00:00.123400Z|0.000000|-180.000000").hexdigest()
    assert tews_source_key("2026-11-16T10:00:00.1234+07:00", "-0", "+180") == expected
    assert tews_source_key("2026-11-16T03:00:00.123400Z", 0, "-180.0") == expected
    assert tews_source_key("2026-11-16T03:00:00.1234Z", -0.0000004, "179.9999995") == expected
    assert canonical_decimal_coord(Decimal("-0.0000005"), "latitude") == "-0.000001"
    assert canonical_decimal_coord("1.2345675", "latitude") == "1.234568"


@pytest.mark.parametrize(
    "value",
    [
        "2026-11-16T03:00:00.1234560Z",
        "2026-11-16T10:00:00,0000001+07:00",
        "2026-11-16T03:00:00",
        "bad-date",
    ],
)
def test_invalid_timestamp_rejected_before_hashing(value):
    with pytest.raises(ValueError):
        tews_source_key(value, 0, 0)


@pytest.mark.parametrize(
    ("latitude", "longitude"),
    [
        ("NaN", 0),
        (0, "Infinity"),
        ("90.00000001", 0),
        (0, "-180.00000001"),
        (True, 0),
    ],
)
def test_tews_rejects_invalid_coordinates_before_rounding(now, latitude, longitude):
    with pytest.raises(ValueError):
        tews_source_key(now, latitude, longitude)


def test_content_hash_matches_canonical_utf8_json():
    payload = {"title": "aér", "samples": [{"b": 2, "a": 1}], "last_seen_at": "yesterday"}
    data = '{"samples":[{"a":1,"b":2}],"title":"aér"}'.encode()
    expected = hashlib.sha256(data).hexdigest()
    assert compute_content_hash(payload) == expected
    assert (
        compute_content_hash({**payload, "first_seen_at": "now", "fetched_at": "now"}) == expected
    )
    assert compute_content_hash({**payload, "samples": [{"a": 2, "b": 1}]}) != expected
    with pytest.raises(ValueError):
        compute_content_hash({"magnitude": math.nan})


def test_haversine_at_zero_antipodes_and_antimeridian():
    assert haversine_km(80, -180, 80, 180) == 0
    assert haversine_km(90, -80, 90, 75) == 0
    assert haversine_km(0, 0, 0, 180) == pytest.approx(math.pi * EARTH_RADIUS_KM)
    distance = haversine_km(0, 179.9, 0, -179.9)
    assert distance == pytest.approx(22.239016, abs=0.000001)
    assert is_within_radius(distance, 25)


@pytest.mark.parametrize("radius", [25, 50, 100])
def test_inclusive_radius_and_bbox_cover_the_tolerance_band(radius):
    cutoff = radius + RADIUS_TOLERANCE_KM
    assert is_within_radius(radius, radius)
    assert is_within_radius(cutoff, radius)
    assert not is_within_radius(math.nextafter(cutoff, math.inf), radius)
    assert not is_within_radius(radius + 0.001, radius)
    box = zone_bounding_box(0, 0, radius)
    for km in (radius, cutoff):
        degrees = math.degrees(km / EARTH_RADIUS_KM)
        assert haversine_km(0, 0, degrees, 0) == pytest.approx(km)
        assert box.south <= -degrees <= degrees <= box.north
        assert box.west <= -degrees <= degrees <= box.east


@pytest.mark.parametrize(
    ("lat", "lon", "radius", "all_lons"),
    [
        (0, 179.9, 25, False),
        (78, -179, 100, False),
        (89.9, 40, 25, True),
        (-89.9, 40, 50, True),
    ],
)
def test_zone_bbox_contains_points_in_all_directions(lat, lon, radius, all_lons):
    box = zone_bounding_box(lat, lon, radius)
    if all_lons:
        assert (box.west, box.east) == (-180, 180)
    else:
        assert box.crosses_antimeridian
    # Forward spherical destination from an independent bearing and arc length.
    phi, arc = math.radians(lat), (radius + RADIUS_TOLERANCE_KM) / EARTH_RADIUS_KM
    for bearing in range(360):
        angle = math.radians(bearing)
        dest = math.asin(
            math.sin(phi) * math.cos(arc) + math.cos(phi) * math.sin(arc) * math.cos(angle)
        )
        offset = math.atan2(
            math.sin(angle) * math.sin(arc) * math.cos(phi),
            math.cos(arc) - math.sin(phi) * math.sin(dest),
        )
        longitude = (lon + math.degrees(offset) + 180) % 360 - 180
        assert box.south <= math.degrees(dest) <= box.north
        if box.crosses_antimeridian:
            assert longitude >= box.west or longitude <= box.east
        else:
            assert box.west <= longitude <= box.east


@pytest.fixture
def concave():
    return analyze_polygon([(0, 0), (0, 3), (1, 3), (1, 1), (3, 1), (3, 0)])


def test_concave_polygon_centroid_and_second_area_match(concave):
    assert concave.geometry_valid
    assert concave.centroid_latitude == pytest.approx(1.1)
    assert concave.centroid_longitude == pytest.approx(1.1)
    assert (concave.south, concave.north, concave.west, concave.east) == (0, 3, 0, 3)
    assert concave.crosses_antimeridian is False
    assert match_cap_areas(2, 2, 25, [concave])["within_radius"] is False
    second = analyze_polygon([(1, 1), (1, 3), (3, 3), (3, 1), (1, 1)])
    assert match_cap_areas(2, 2, 25, [concave, second]) == {
        "match_method": "inside_polygon",
        "match_distance_km": 0.0,
        "within_radius": True,
    }


@pytest.mark.parametrize("point", [(0, 0), (0, 2), (-BOUNDARY_TOLERANCE_DEG, 2), (1, 2)])
def test_includes_edge_and_vertex_with_tolerance(concave, point):
    assert match_cap_areas(*point, 25, [concave])["match_method"] == "inside_polygon"
    assert match_cap_areas(-2e-9, 2, 25, [concave])["match_method"] == "near_polygon_sample"


@pytest.mark.parametrize("reverse", [True, False])
def test_crossing_ring_uses_the_same_longitude_branch(reverse):
    ring = [(-1, 179), (-1, -179), (1, -179), (1, 179)]
    polygon = analyze_polygon(reversed(ring) if reverse else ring)
    assert polygon.geometry_valid
    assert polygon.crosses_antimeridian is True
    assert (polygon.west, polygon.east) == (179, -179)
    assert (polygon.centroid_latitude, polygon.centroid_longitude) == (0, -180)
    assert [v.sequence for v in polygon.vertices] == [1, 2, 3, 4, 5]
    assert polygon.vertices[0].latitude == polygon.vertices[-1].latitude
    assert polygon.vertices[0].longitude == polygon.vertices[-1].longitude
    assert polygon.unwrapped_ring[0] == polygon.unwrapped_ring[-1]
    for lon in (179.5, -179.5, 180, -180):
        assert match_cap_areas(0, lon, 25, [polygon])["match_method"] == "inside_polygon"
    assert match_cap_areas(0, 0, 25, [polygon])["within_radius"] is False


def test_long_edge_sample_can_miss_circle_intersection():
    polygon = analyze_polygon([(0, -5), (0, 5), (2, 5), (2, -5)])
    assert haversine_km(-0.01, 0, 0, 0) < 25  # The middle of the edge is close.
    match = match_cap_areas(-0.01, 0, 25, [polygon])
    assert match["match_method"] == "near_polygon_sample"
    assert match["match_distance_km"] == pytest.approx(haversine_km(-0.01, 0, 1, 0))
    assert match["within_radius"] is False
    near_vertex = match_cap_areas(-0.01, 5, 25, [polygon])
    assert near_vertex["match_distance_km"] == pytest.approx(haversine_km(-0.01, 5, 0, 5))
    assert near_vertex["within_radius"] is True


def test_nearest_sample_across_disjoint_polygons_is_order_independent():
    first = analyze_polygon([(-5, 10), (-5, 12), (-3, 10)])
    invalid = analyze_polygon([])
    second = analyze_polygon([(0, 179.8), (0, -179.9), (2, 179.8)])
    for polygons in ([first, invalid, second], [second, invalid, first]):
        result = match_cap_areas(0, -179.8, 25, polygons)
        assert result["match_method"] == "near_polygon_sample"
        assert result["within_radius"] is True
        assert result["match_distance_km"] == pytest.approx(haversine_km(0, -179.8, 0, -179.9))


def test_wrapped_polygon_bounds_include_original_endpoints():
    polygon = analyze_polygon([(0, -179.5), (0, 178.2), (1, 178.2)])
    assert polygon.geometry_valid
    assert (polygon.west, polygon.east) == (178.2, -179.5)


def test_maximum_closed_ring_is_accepted_without_truncation():
    # Many collinear samples on one side of a valid triangle.
    ring = [(0, 10 * i / MAX_CAP_VERTICES) for i in range(MAX_CAP_VERTICES - 2)]
    ring.extend([(1, 0), ring[0]])
    result = analyze_polygon(ring)
    assert result.geometry_valid
    assert len(result.vertices) == MAX_CAP_VERTICES


@pytest.mark.parametrize(
    ("ring", "reason"),
    [
        ([(0, 0), (1, 1), (0, 0)], "too_few_vertices"),
        ([(0, 0), (1, 1), (2, 2)], "degenerate_area"),
        ([(0, 179), (2, -179), (2, 179), (0, -179)], "self_intersection"),
        ([(80, 0), (81, 120), (80, -120)], "unsupported_polar_wrap"),
        ([(0, 0), (0, 1), (math.nan, 1)], "invalid_coordinate"),
        ([(0, 0), (0, math.inf), (1, 1)], "invalid_coordinate"),
        ([(0, 0), (0, 181), (1, 1)], "invalid_coordinate"),
        ([(91, 0), (0, 1), (1, 1)], "invalid_coordinate"),
        ([(0, 0)] * (MAX_CAP_VERTICES + 1), "too_many_vertices"),
    ],
)
def test_invalid_ring_has_no_location_claim(ring, reason):
    polygon = analyze_polygon(ring)
    assert not polygon.geometry_valid
    assert polygon.reason == reason
    assert (polygon.south, polygon.north, polygon.west, polygon.east) == (None,) * 4
    assert (
        polygon.crosses_antimeridian,
        polygon.centroid_longitude,
        polygon.centroid_latitude,
    ) == (None,) * 3
    assert match_cap_areas(0, 0, 50, [polygon]) == {
        "match_method": "no_geometry",
        "match_distance_km": None,
        "within_radius": None,
    }


@pytest.fixture
def quake(now):
    return dict(
        distance_km=10,
        radius_km=50,
        magnitude=5,
        occurred_at=now - timedelta(hours=2),
        evaluated_at=now,
        zone_version=7,
    )


def test_earthquake_priority_frozen_example(quake):
    priority = evaluate_earthquake_priority(**quake)
    assert priority["priority_algo"] == "eq-priority-v1"
    assert priority["priority_score"] == 74.25
    assert priority["priority_display"] == "74.3"
    assert priority["priority_label"] == "high"
    assert priority["components"] == {
        "p": 0.8,
        "m": 0.5,
        "t": 22 / 24,
        "age_hours": 2,
        "magnitude": 5,
        "radius_km": 50,
    }
    assert priority["evaluated_at"] == "2026-11-16T03:00:00.000000Z"
    assert priority["zone_version"] == 7
    assert priority["match_method"] == "point_distance"
    assert priority["match_distance_km"] == 10
    assert priority["within_radius"] is True
    assert [(r["code"], r["values"]) for r in priority["priority_reasons"]] == [
        ("distance_radius", {"distance_km": 10, "radius_km": 50}),
        ("magnitude", {"magnitude": 5}),
        ("age", {"age_hours": 2}),
        ("application_priority", {"priority_label": "high"}),
    ]


@pytest.mark.parametrize(
    ("distance", "score", "display", "label"),
    [
        (25, 35, "35.0", "attention"),
        (25.001, 34.9988, "35.0", "ordinary"),
        (0, 65, "65.0", "high"),
        (0.001, 64.9988, "65.0", "attention"),
    ],
)
def test_quake_label_uses_unrounded_score(now, quake, distance, score, display, label):
    quake.update(magnitude=2, distance_km=distance, occurred_at=now - timedelta(days=1))
    result = evaluate_earthquake_priority(**quake)
    assert result["priority_score"] == pytest.approx(score)
    assert (result["priority_display"], result["priority_label"]) == (display, label)


@pytest.mark.parametrize(
    ("field", "invalid"),
    [
        ("magnitude", None),
        ("magnitude", math.nan),
        ("magnitude", -1),
        ("distance_km", None),
        ("radius_km", 0),
        ("radius_km", math.inf),
        ("occurred_at", "invalid"),
    ],
)
def test_unavailable_quake_keeps_valid_match_and_explains_missing_input(quake, field, invalid):
    quake[field] = invalid
    result = evaluate_earthquake_priority(**quake)
    for key in ("priority_score", "priority_display", "components"):
        assert result[key] is None
    assert result["priority_label"] == "unavailable"
    reasons = result["priority_reasons"]
    assert [r["code"] for r in reasons] == [
        "distance_radius",
        "magnitude",
        "age",
        "missing_data",
        "application_priority",
    ]
    assert reasons[-2]["values"] == {"fields": [field]}
    if field in ("occurred_at", "magnitude"):
        assert result["within_radius"] is True
        assert result["match_distance_km"] == 10
    else:
        assert result["within_radius"] is None


@pytest.mark.parametrize(
    ("offset", "status", "hours"),
    [
        (timedelta(minutes=3), "current", 0),
        (timedelta(minutes=5), "current", 0),
        (timedelta(minutes=5, microseconds=1), "invalid_time", None),
        (timedelta(minutes=6), "invalid_time", None),
        (-timedelta(hours=24), "current", 24),
        (-timedelta(hours=24, microseconds=1), "historical", 24 + 1e-6 / 3600),
    ],
)
def test_earthquake_age_boundaries(now, quake, offset, status, hours):
    quake["occurred_at"] = now + offset
    assert earthquake_lifecycle_status(now + offset, now) == status
    result = evaluate_earthquake_priority(**quake)
    if hours is None:
        assert result["priority_label"] == "unavailable"
        assert result["components"] is None
        assert result["priority_reasons"][-2]["values"] == {"fields": ["occurred_at"]}
    else:
        assert result["components"]["age_hours"] == pytest.approx(hours)


def test_historical_distant_quake_clamps_components_and_still_has_score(now, quake):
    quake.update(distance_km=75, magnitude=12, occurred_at=now - timedelta(days=2))
    result = evaluate_earthquake_priority(**quake)
    assert result["within_radius"] is False
    assert result["priority_score"] == 25
    assert result["components"] == dict(p=0, m=1, t=0, magnitude=12, radius_km=50, age_hours=48)


@pytest.fixture
def cap(now):
    return dict(msg_type="Alert", sent=now, expires=now + timedelta(hours=3), evaluated_at=now)


@pytest.mark.parametrize(
    ("changes", "status"),
    [
        ({"msg_type": "Cancel", "superseded": True, "expires": None}, "cancelled"),
        ({"cancelled": True, "superseded": True}, "cancelled"),
        ({"superseded": True, "lifecycle_complete": False}, "superseded"),
        ({"lifecycle_complete": False, "expires": "2000-01-01T00:00:00Z"}, "incomplete"),
        ({"msg_type": "Error"}, "incomplete"),
        ({"msg_type": "Ack"}, "incomplete"),
        ({"msg_type": "Update"}, "incomplete"),
        ({"msg_type": "Update", "lifecycle_complete": True}, "active"),
        ({"effective": "bad timestamp"}, "incomplete"),
        ({"expires": None}, "incomplete"),
        ({"expires": "2026-11-16T03:00:00Z"}, "incomplete"),  # Zero-length interval.
        ({"effective": "2027-01-01T00:00:00Z"}, "incomplete"),
        ({"sent": "2026-11-16T01:00:00Z", "expires": "2026-11-16T03:00:00Z"}, "expired"),
        ({"effective": "2026-11-16T03:00:00.000001Z"}, "scheduled"),
        ({"effective": "2026-11-16T10:00:00+07:00"}, "active"),
    ],
)
def test_cap_lifecycle_precedence(cap, changes, status):
    assert cap_lifecycle_status(**(cap | changes)) == status


@pytest.mark.parametrize(
    ("severity", "active_label"),
    [
        ("Extreme", "high"),
        ("Severe", "high"),
        ("Moderate", "attention"),
        ("Minor", "information"),
        ("Unknown", "unavailable"),
        (None, "unavailable"),
    ],
)
@pytest.mark.parametrize(
    ("method", "distance", "within"),
    [
        ("inside_polygon", 0, True),
        ("near_polygon_sample", 12.5, True),
        ("near_polygon_sample", 120, False),
        ("no_geometry", None, None),
    ],
)
@pytest.mark.parametrize(
    "lifecycle",
    [
        "active",
        "scheduled",
        "incomplete",
        "expired",
        "superseded",
        "cancelled",
    ],
)
def test_cap_priority_matrix(now, cap, severity, active_label, method, distance, within, lifecycle):
    changes = {
        "active": {},
        "scheduled": {"effective": now + timedelta(hours=1)},
        "incomplete": {"expires": None},
        "superseded": {"superseded": True},
        "cancelled": {"cancelled": True},
        "expired": {"sent": now - timedelta(days=1), "expires": now},
    }[lifecycle]
    cap.update(changes)
    match = {"match_method": method, "match_distance_km": distance, "within_radius": within}
    result = evaluate_cap_priority(
        **cap,
        status="Actual",
        severity=severity,
        urgency="Immediate",
        certainty="Likely",
        match=match,
        area_descriptions=["Area A", "Area B"],
        zone_version=9,
    )
    assert result["priority_algo"] == "cap-priority-v1"
    assert result["priority_label"] == (
        active_label if lifecycle == "active" and within else "unavailable"
    )
    for key in ("components", "priority_score", "priority_display"):
        assert result[key] is None
    assert {k: result[k] for k in match} == match
    assert result["zone_version"] == 9
    assert result["evaluated_at"] == parse_utc_timestamp(now)
    validity = {
        "lifecycle_status": lifecycle,
        "effective": parse_utc_timestamp(cap.get("effective", cap["sent"])),
        "expires": parse_utc_timestamp(cap["expires"]) if cap["expires"] else None,
    }
    reasons = result["priority_reasons"]
    assert all(reason["text"] for reason in reasons)
    assert [(r["code"], r["values"]) for r in reasons] == [
        ("area", {"area_descriptions": ["Area A", "Area B"]}),
        ("location_match", match),
        ("severity", {"severity": severity}),
        ("urgency_certainty", {"urgency": "Immediate", "certainty": "Likely"}),
        ("validity", validity),
    ]


@pytest.mark.parametrize("status", ["Test", "Exercise", "System", "Draft"])
def test_non_actual_cap_never_has_live_priority(cap, status):
    match = dict(match_method="inside_polygon", match_distance_km=0.0, within_radius=True)
    result = evaluate_cap_priority(
        **cap,
        status=status,
        severity="Extreme",
        urgency="other",
        match=match,
        area_descriptions=[],
        zone_version=1,
    )
    assert result["priority_label"] == "unavailable"
    assert result["priority_reasons"][3]["values"] == {"urgency": "Unknown", "certainty": None}
