"""Parse bounded BMKG documents into normalized records without database access."""

import json
import math
import re
from dataclasses import dataclass, field
from datetime import datetime
from urllib.parse import urljoin
from xml.etree import ElementTree as ET

from app.services import radar
from app.services.bmkg_fetch import MAX_BYTES, checked_url

TEWS = "BMKG_TEWS"
NOWCAST = "BMKG_NOWCAST"
TEWS_BASE = "https://data.bmkg.go.id/DataMKG/TEWS/"
TEWS_URLS = tuple(
    TEWS_BASE + name + ".json" for name in ("autogempa", "gempaterkini", "gempadirasakan")
)
RSS = "https://www.bmkg.go.id/alerts/nowcast/id"
CAP = "{urn:oasis:names:tc:emergency:cap:1.2}"
ENUMS = {
    "severity": {"Extreme", "Severe", "Moderate", "Minor", "Unknown"},
    "urgency": {"Immediate", "Expected", "Future", "Past", "Unknown"},
    "certainty": {"Observed", "Likely", "Possible", "Unlikely", "Unknown"},
}


@dataclass
class Record:
    fields: dict
    provenance: dict
    areas: list[tuple[str, list[radar.PolygonAnalysis]]] = field(default_factory=list)
    references: list[tuple[str, str, datetime]] = field(default_factory=list)
    references_valid: bool = True


def clean(value):
    if isinstance(value, (str, int, float)) and not isinstance(value, bool):
        value = str(value).strip()
        if value and value != "-" and "\x00" not in value:
            return value
    return None


def timestamp(value):
    return datetime.fromisoformat(radar.parse_utc_timestamp(value))


def number(value):
    if isinstance(value, bool):
        return None
    try:
        n = float(value)
    except TypeError, ValueError, OverflowError:
        return None
    return n if math.isfinite(n) and n >= 0 else None


def tews_rows(body):
    data = json.loads(body.decode("utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("Infogempa"), dict):
        raise ValueError("Invalid TEWS envelope")
    rows = data["Infogempa"].get("gempa")
    if isinstance(rows, dict):
        return [rows]
    if not isinstance(rows, list):
        raise ValueError("Missing earthquake list")
    return rows


def parse_quake(row, url):
    if not isinstance(row, dict) or not isinstance(row.get("Coordinates"), str):
        raise ValueError("Invalid earthquake")
    lat, lon = row["Coordinates"].split(",")
    when = timestamp(row.get("DateTime"))
    key = radar.tews_source_key(when, lat, lon)
    fields = {
        name: clean(row.get(source))
        for name, source in {
            "region": "Wilayah",
            "latitude_text": "Lintang",
            "longitude_text": "Bujur",
            "potential": "Potensi",
            "felt": "Dirasakan",
        }.items()
    }
    shakemap = clean(row.get("Shakemap"))
    depth = clean(row.get("Kedalaman"))
    fields.update(
        source=TEWS,
        source_key=key,
        category="earthquake",
        occurred_at=when,
        latitude=float(radar.canonical_decimal_coord(lat, "latitude")),
        longitude=float(radar.canonical_decimal_coord(lon, "longitude")),
        magnitude=number(row.get("Magnitude")),
        depth_km=number(re.sub(r"(?i)\s*km$", "", depth)) if depth else None,
        shakemap_url=str(checked_url(urljoin(TEWS_BASE, shakemap))) if shakemap else None,
        source_url=url,
    )
    return Record(fields, {"endpoints": [url]})


def xml_root(body):
    if len(body) > MAX_BYTES:
        raise ValueError("XML too large")
    content = body.decode("utf-8-sig")
    if "\x00" in content or re.search(r"<!\s*(DOCTYPE|ENTITY)\b", content, re.I):
        raise ValueError("Unsafe XML")
    encoding = re.match(r"""<\?xml\s+[^?]*?encoding\s*=\s*["']([^"']+)""", content, re.I)
    if encoding and encoding[1].lower() != "utf-8":
        raise ValueError("Unsupported XML encoding")
    parser = ET.XMLPullParser(events=("start", "end"))
    depth = nodes = vertices = 0
    root = None
    try:
        for offset in range(0, len(content), 8192):
            parser.feed(content[offset : offset + 8192])
            for kind, el in parser.read_events():
                if kind == "start":
                    if root is None:
                        root = el
                    depth += 1
                    nodes += 1
                    if depth > 32 or nodes > 50_000:
                        raise ValueError("XML structure limit")
                else:
                    depth -= 1
                    if el.tag == CAP + "polygon":
                        vertices += len((el.text or "").split())
                        if vertices > radar.MAX_CAP_VERTICES:
                            raise ValueError("CAP vertex limit")
        parser.close()
    except ET.ParseError as exc:
        raise ValueError("Malformed XML") from exc
    return root


def rss_items(body):
    root = xml_root(body)
    if root.tag != "rss" or root.find("channel") is None:
        raise ValueError("Invalid RSS")
    return [
        {
            key: clean(item.findtext(key))
            for key in ("guid", "link", "pubDate", "title", "description")
        }
        for item in root.findall("./channel/item")
    ]


def cap_text(node, name):
    return clean(node.findtext(CAP + name)) if node is not None else None


def parse_cap(body, url, item):
    root = xml_root(body)
    if root.tag != CAP + "alert":
        raise ValueError("Invalid CAP namespace")
    key, sender, status, kind = (
        cap_text(root, k) for k in ("identifier", "sender", "status", "msgType")
    )
    if (
        not key
        or len(key) > 1024
        or not sender
        or status not in {"Actual", "Test", "Draft", "Exercise", "System"}
        or kind not in {"Alert", "Update", "Cancel", "Ack", "Error"}
    ):
        raise ValueError("Invalid CAP header")
    sent = timestamp(cap_text(root, "sent"))
    infos = root.findall(CAP + "info")
    info = next(
        (i for i in infos if (cap_text(i, "language") or "").lower().startswith("id")),
        infos[0] if infos else None,
    )
    start = cap_text(info, "effective")
    end = cap_text(info, "expires")
    effective = timestamp(start) if start else sent
    try:
        expires = timestamp(end) if end else None
    except ValueError:
        expires = None
    fields = {k: cap_text(info, k) for k in ("language", "headline", "description", *ENUMS)}
    provenance = {"rss": item}
    for name, known in ENUMS.items():
        if fields[name] and fields[name] not in known:
            provenance[name] = fields[name]
            fields[name] = "Unknown"
    fields.update(
        source=NOWCAST,
        source_key=key,
        source_url=url,
        category="extreme_weather",
        occurred_at=sent,
        sent=sent,
        sender=sender,
        status=status,
        msg_type=kind,
        effective=effective,
        expires=expires,
        cap_event=cap_text(info, "event"),
        web_url=cap_text(info, "web"),
        latitude=None,
        longitude=None,
        event_code=cap_text(info.find(CAP + "eventCode") if info is not None else None, "value"),
    )
    fields["title"] = (fields["headline"] or fields["cap_event"] or key)[:500]
    record = Record(fields, provenance)
    for area in info.findall(CAP + "area") if info is not None else []:
        desc = cap_text(area, "areaDesc")
        if not desc:
            raise ValueError("Missing CAP area description")
        polygons = []
        for polygon in area.findall(CAP + "polygon"):
            analysis = radar.analyze_polygon(p.split(",") for p in (polygon.text or "").split())
            polygons.append(analysis)
            if analysis.geometry_valid and fields["latitude"] is None:
                fields.update(
                    latitude=analysis.centroid_latitude, longitude=analysis.centroid_longitude
                )
        record.areas.append((desc, polygons))
    if kind in ("Update", "Cancel"):
        unique_refs = set()
        for triple in (cap_text(root, "references") or "").split():
            try:
                author, target, when = triple.split(",")
                if not author or not target or len(target) > 1024:
                    raise ValueError("Invalid reference")
                ref = (author, target, timestamp(when))
                if ref not in unique_refs:
                    record.references.append(ref)
                    unique_refs.add(ref)
            except ValueError:
                record.references_valid = False
    return record
