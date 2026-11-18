"""Collect one source outside the database transaction."""

import hashlib
import zlib
from dataclasses import dataclass, field

import httpx

from app.services import bmkg_parser as parser
from app.services import radar
from app.services.bmkg_fetch import check_time, checked_url

SOURCE_ERRORS = (ValueError, OSError, httpx.HTTPError, zlib.error, RecursionError)


@dataclass
class Batch:
    records: dict[str, parser.Record] = field(default_factory=dict)
    checkpoint: dict = field(default_factory=dict)
    invalid: int = 0
    fetched: int = 0
    error: str | None = None

    @property
    def status(self):
        if self.error or self.invalid:
            return "partial" if self.fetched or self.records else "failed"
        return "success"


def collect_tews(batch, fetcher, deadline):
    digests = dict(batch.checkpoint.get("endpoints", {}))
    for url in parser.TEWS_URLS:
        try:
            body = fetcher.get(url, deadline)
            rows = parser.tews_rows(body)
            batch.fetched += 1
            invalid_before = batch.invalid
            for row in rows:
                check_time(deadline)
                try:
                    record = parser.parse_quake(row, url)
                except ValueError:
                    batch.invalid += 1
                    continue
                key = record.fields["source_key"]
                existing = batch.records.setdefault(key, record)
                if existing is not record:
                    if url not in existing.provenance["endpoints"]:
                        existing.provenance["endpoints"].append(url)
                    for name, value in record.fields.items():
                        if existing.fields[name] is None:
                            existing.fields[name] = value
            if batch.invalid == invalid_before:
                digests[url] = hashlib.sha256(body).hexdigest()
        except SOURCE_ERRORS:
            batch.error = "TEWS_DOCUMENT_FAILED"
    batch.checkpoint = {"endpoints": digests}


def collect_nowcast(batch, fetcher, deadline):
    items = parser.rss_items(fetcher.get(parser.RSS, deadline))
    prior = batch.checkpoint.get("items", {})
    failed_before = set(batch.checkpoint.get("retry", []))
    seen = {}
    pending = {}
    # Retain deferred links when the next RSS snapshot has already rotated them out.
    for item in [*batch.checkpoint.get("backlog", []), *items]:
        try:
            url = checked_url(item["link"] or "")
            if not url.path.endswith("_alert.xml"):
                raise ValueError("Invalid CAP link")
        except ValueError, httpx.InvalidURL:
            batch.invalid += 1
            continue
        link = str(url)
        fingerprint = radar.compute_content_hash(item)
        if prior.get(link) == fingerprint:
            seen[link] = fingerprint
        else:
            pending[link] = (fingerprint, item)
    retry = []
    # Give unattempted documents precedence over persistent failures.
    ordered = sorted(pending, key=lambda link: link in failed_before)
    for link in ordered[:50]:
        fingerprint, item = pending[link]
        try:
            record = parser.parse_cap(fetcher.get(link, deadline), link, item)
            batch.records[record.fields["source_key"]] = record
            seen[link] = fingerprint
        except SOURCE_ERRORS:
            retry.append(link)
            batch.invalid += 1
    if len(pending) > 50:
        batch.error = "CAP_BACKLOG"
    batch.fetched = int(bool(seen) or not items)
    batch.checkpoint = {
        "items": seen,
        "retry": retry + [u for u in ordered[50:] if u in failed_before],
        "backlog": [pending[u][1] for u in ordered[50:]],
    }


def collect(source, checkpoint, fetcher, deadline):
    batch = Batch(checkpoint=dict(checkpoint))
    try:
        if source == parser.TEWS:
            collect_tews(batch, fetcher, deadline)
        else:
            collect_nowcast(batch, fetcher, deadline)
        check_time(deadline)
    except SOURCE_ERRORS:
        batch.error = "SOURCE_DOCUMENT_FAILED"
    return batch
