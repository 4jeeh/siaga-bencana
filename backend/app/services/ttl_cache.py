from threading import Lock
from time import monotonic


class TTLCache[K, V]:
    def __init__(self, ttl: int):
        self.ttl = ttl
        self.entries: dict[K, tuple[float, V]] = {}
        self.lock = Lock()

    def get(self, key: K) -> V | None:
        with self.lock:
            entry = self.entries.get(key)
            if entry is not None:
                expires, value = entry
                if monotonic() < expires:
                    return value
                del self.entries[key]
            return None

    def put(self, key: K, value: V):
        with self.lock:
            self.entries.pop(key, None)
            if len(self.entries) >= 256:
                del self.entries[next(iter(self.entries))]
            self.entries[key] = (monotonic() + self.ttl, value)
