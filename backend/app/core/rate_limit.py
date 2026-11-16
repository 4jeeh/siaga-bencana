import math
import threading
import time
from collections import deque

from app.core.errors import ApiError


class RateLimiter:
    """Rolling window, one process. Peer IP only; never trust arbitrary forwarded headers."""

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.buckets = {}
        self.lock = threading.Lock()
        self.last_cleanup = 0.0

    def check(self, key: str, limit: int):
        now = self.clock()
        with self.lock:
            if now - self.last_cleanup >= 60:
                self.buckets = {k: v for k, v in self.buckets.items() if v and v[-1] > now - 60}
                self.last_cleanup = now
            bucket = self.buckets.setdefault(key, deque())
            while bucket and bucket[0] <= now - 60:
                bucket.popleft()
            if len(bucket) >= limit:
                raise ApiError(
                    429,
                    "RATE_LIMITED",
                    "Terlalu banyak permintaan. Coba lagi nanti.",
                    headers={"Retry-After": str(max(1, math.ceil(bucket[0] + 60 - now)))},
                )
            bucket.append(now)
