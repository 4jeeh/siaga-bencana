from threading import Lock
from time import monotonic

import httpx

from app.schemas.locations import LocationSearchData, LocationSuggestion
from app.services.ttl_cache import TTLCache

# Representative points for offline zone selection.
LOCAL_PLACES = (
    ("Jakarta Pusat", "DKI Jakarta", -6.1818, 106.8223),
    ("Jakarta Selatan", "DKI Jakarta", -6.2615, 106.8106),
    ("Jakarta Timur", "DKI Jakarta", -6.2250, 106.9004),
    ("Jakarta Barat", "DKI Jakarta", -6.1683, 106.7588),
    ("Jakarta Utara", "DKI Jakarta", -6.1384, 106.8637),
    ("Bandung", "Jawa Barat", -6.9175, 107.6191),
    ("Kec. Coblong Bandung", "Kota Bandung, Jawa Barat", -6.8861, 107.6153),
    ("Bekasi", "Jawa Barat", -6.2383, 106.9756),
    ("Bogor", "Jawa Barat", -6.5950, 106.8166),
    ("Depok", "Jawa Barat", -6.4025, 106.7942),
    ("Cirebon", "Jawa Barat", -6.7320, 108.5523),
    ("Tasikmalaya", "Jawa Barat", -7.3274, 108.2207),
    ("Tangerang", "Banten", -6.1783, 106.6319),
    ("Tangerang Selatan", "Banten", -6.2889, 106.7181),
    ("Serang", "Banten", -6.1201, 106.1503),
    ("Semarang", "Jawa Tengah", -6.9667, 110.4167),
    ("Surakarta", "Jawa Tengah", -7.5666, 110.8167),
    ("Yogyakarta", "DI Yogyakarta", -7.7956, 110.3695),
    ("Sleman", "DI Yogyakarta", -7.7162, 110.3555),
    ("Bantul", "DI Yogyakarta", -7.8880, 110.3280),
    ("Surabaya", "Jawa Timur", -7.2575, 112.7521),
    ("Malang", "Jawa Timur", -7.9666, 112.6326),
    ("Sidoarjo", "Jawa Timur", -7.4478, 112.7183),
    ("Gresik", "Jawa Timur", -7.1560, 112.6560),
    ("Banyuwangi", "Jawa Timur", -8.2192, 114.3692),
    ("Denpasar", "Bali", -8.6500, 115.2167),
    ("Badung", "Bali", -8.5811, 115.1770),
    ("Mataram", "Nusa Tenggara Barat", -8.5833, 116.1167),
    ("Kupang", "Nusa Tenggara Timur", -10.1772, 123.6070),
    ("Medan", "Sumatera Utara", 3.5952, 98.6722),
    ("Banda Aceh", "Aceh", 5.5483, 95.3238),
    ("Padang", "Sumatera Barat", -0.9471, 100.4172),
    ("Pekanbaru", "Riau", 0.5071, 101.4478),
    ("Batam", "Kepulauan Riau", 1.1301, 104.0529),
    ("Palembang", "Sumatera Selatan", -2.9761, 104.7754),
    ("Jambi", "Jambi", -1.6101, 103.6131),
    ("Bengkulu", "Bengkulu", -3.7928, 102.2608),
    ("Bandar Lampung", "Lampung", -5.4292, 105.2610),
    ("Balikpapan", "Kalimantan Timur", -1.2379, 116.8529),
    ("Samarinda", "Kalimantan Timur", -0.5022, 117.1536),
    ("Banjarmasin", "Kalimantan Selatan", -3.3194, 114.5900),
    ("Pontianak", "Kalimantan Barat", -0.0263, 109.3425),
    ("Palangkaraya", "Kalimantan Tengah", -2.2096, 113.9213),
    ("Makassar", "Sulawesi Selatan", -5.1477, 119.4327),
    ("Manado", "Sulawesi Utara", 1.4748, 124.8421),
    ("Palu", "Sulawesi Tengah", -0.9003, 119.8779),
    ("Kendari", "Sulawesi Tenggara", -3.9985, 122.5120),
    ("Gorontalo", "Gorontalo", 0.5435, 123.0568),
    ("Ambon", "Maluku", -3.6954, 128.1814),
    ("Ternate", "Maluku Utara", 0.7905, 127.3842),
    ("Jayapura", "Papua", -2.5337, 140.7181),
    ("Sorong", "Papua Barat Daya", -0.8762, 131.2558),
    ("Merauke", "Papua Selatan", -8.4932, 140.4018),
)


def local_search(q, limit):
    items = []
    for label, subtitle, latitude, longitude in LOCAL_PLACES:
        if q in label.casefold() or q in subtitle.casefold():
            items.append(LocationSuggestion(
                label=label, subtitle=subtitle, latitude=latitude, longitude=longitude,
                source="LOCAL_FALLBACK",
            ))
            if len(items) == limit:
                break
    return LocationSearchData(items=items)


def nominatim_search(q, limit):
    response = httpx.get(
        "https://nominatim.openstreetmap.org/search",
        params={
            "q": q, "format": "jsonv2", "addressdetails": "1", "countrycodes": "id",
            "accept-language": "id", "limit": str(limit),
        },
        headers={"User-Agent": "SiagaBencana/1.0 (UAS Pemrograman Aplikasi Bergerak)"},
        timeout=4.0, follow_redirects=False,
    )
    if response.status_code != 200:
        return None
    rows = response.json()
    if not isinstance(rows, list) or not rows:
        return None
    items = []
    for row in rows[:limit]:
        if not isinstance(row, dict) or not isinstance(row.get("display_name"), str):
            return None
        label, _, subtitle = row["display_name"].partition(",")
        if not label.strip():
            return None
        items.append(LocationSuggestion(
            label=label.strip(), subtitle=subtitle.strip() or None,
            latitude=row["lat"], longitude=row["lon"], source="NOMINATIM",
        ))
    return LocationSearchData(items=items)


class LocationService:
    def __init__(self):
        self.cache = TTLCache[tuple[str, int], LocationSearchData](900)
        self.lock = Lock()
        self.next_request = 0.0

    def search(self, query, settings):
        key = (query.q.casefold(), query.limit)
        if settings.app_mode == "simulation":
            return local_search(*key)
        cached = self.cache.get(key)
        if cached is not None:
            return cached
        with self.lock:
            now = monotonic()
            if now < self.next_request:
                return local_search(*key)
            self.next_request = now + 1.0
        try:
            result = nominatim_search(query.q, query.limit)
        except (httpx.HTTPError, ValueError, KeyError, TypeError, OverflowError, RecursionError):
            result = None
        result = result or local_search(*key)
        self.cache.put(key, result)
        return result
