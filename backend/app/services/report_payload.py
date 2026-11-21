import json
import re
import unicodedata
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from hashlib import sha256
from uuid import UUID

from app.core.errors import ApiError

PAYLOAD_HASH_ALGO = "report-payload-v1"
CATEGORIES = frozenset({"earthquake", "flood", "eruption", "extreme_weather", "haze_other"})


def _invalid(field: str) -> ApiError:
    return ApiError(422, "VALIDATION_ERROR", "Isian laporan tidak valid.", {"field": field})


def _uuid(raw: str | UUID, field: str) -> UUID:
    try:
        return UUID(str(raw))
    except ValueError:
        raise _invalid(field) from None


def _coordinate(raw: str, field: str, bound: int) -> tuple[float, str]:
    try:
        value = Decimal(raw)
        if not value.is_finite() or not -bound <= value <= bound:
            raise _invalid(field)
        value = value.quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)
    except InvalidOperation, TypeError, ValueError:
        raise _invalid(field) from None
    if value == 0:
        value = value.copy_abs()
    elif field == "longitude" and value == 180:
        value = -value
    return float(value), format(value, ".6f")


def compute_payload_hash(
    *,
    category: str,
    description: str,
    event_id: UUID | None,
    latitude: str,
    longitude: str,
    photo_sha256: str | None,
) -> str:
    """Hash canonical fields only. Coordinates are fixed-six decimal strings."""
    fields = dict(
        algo=PAYLOAD_HASH_ALGO,
        category=category,
        description=description,
        event_id=str(event_id) if event_id else None,
        latitude=latitude,
        longitude=longitude,
        photo_sha256=photo_sha256,
    )
    encoded = json.dumps(fields, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return sha256(encoded.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class CanonicalReportPayload:
    client_request_id: UUID
    event_id: UUID | None
    category: str
    description: str
    latitude: float
    longitude: float
    lat_fixed6: str
    lon_fixed6: str
    photo_sha256: str | None
    payload_hash: str


def canonicalize_report_payload(
    *,
    client_request_id: str | UUID,
    category: str,
    description: str,
    latitude: str,
    longitude: str,
    event_id: str | UUID | None = None,
    photo_sha256: str | None = None,
) -> CanonicalReportPayload:
    if category not in CATEGORIES:
        raise _invalid("category")
    desc = unicodedata.normalize("NFC", description).strip()
    if not 20 <= len(desc) <= 1000 or "\x00" in desc:
        raise _invalid("description")
    if photo_sha256 is not None and not re.fullmatch("[0-9a-f]{64}", photo_sha256):
        raise _invalid("photo_sha256")
    request_uuid = _uuid(client_request_id, "client_request_id")
    event_uuid = None if event_id is None else _uuid(event_id, "event_id")
    lat, lat_text = _coordinate(latitude, "latitude", 90)
    lon, lon_text = _coordinate(longitude, "longitude", 180)
    digest = compute_payload_hash(
        category=category,
        description=desc,
        event_id=event_uuid,
        latitude=lat_text,
        longitude=lon_text,
        photo_sha256=photo_sha256,
    )
    return CanonicalReportPayload(
        request_uuid, event_uuid, category, desc, lat, lon, lat_text, lon_text, photo_sha256, digest
    )
