"""Bounded downloads for the BMKG worker."""

import ipaddress
import socket
import time
import zlib
from contextlib import contextmanager
from urllib.parse import urljoin

import httpx

MAX_BYTES = 2_097_152
HOSTS = {"data.bmkg.go.id", "www.bmkg.go.id", "bmkg.go.id"}


def public_addresses(host):
    return [row[4][0] for row in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)]


def checked_url(value):
    try:
        url = httpx.URL(value)
    except httpx.InvalidURL as exc:
        raise ValueError("Invalid BMKG URL") from exc
    if (
        url.scheme != "https"
        or url.host not in HOSTS
        or url.port not in (None, 443)
        or url.userinfo
        or len(str(url)) > 2048
    ):
        raise ValueError("Disallowed BMKG URL")
    return url


class PublicTransport(httpx.BaseTransport):
    """Connect to the validated address while verifying TLS for the original BMKG host."""

    def __init__(self):
        self.transport = httpx.HTTPTransport(limits=httpx.Limits(max_keepalive_connections=0))

    def handle_request(self, request):
        pinned = httpx.Request(
            request.method,
            request.url.copy_with(host=request.extensions["bmkg_ip"]),
            headers=request.headers,
            stream=request.stream,
            extensions={**request.extensions, "sni_hostname": request.url.host},
        )
        return self.transport.handle_request(pinned)

    def close(self):
        self.transport.close()


def check_time(deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("BMKG deadline")
    return remaining


def bounded_body(response, deadline):
    if response.is_stream_consumed:  # In-memory HTTPX fixtures
        if len(response.content) > MAX_BYTES:
            raise ValueError("Document too large")
        return response.content
    encoding = response.headers.get("Content-Encoding", "identity").lower()
    if encoding not in ("gzip", "identity"):
        raise ValueError("Unsupported encoding")
    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS) if encoding == "gzip" else None
    result = bytearray()
    for chunk in response.iter_raw():
        check_time(deadline)
        if decoder:
            chunk = decoder.decompress(chunk, MAX_BYTES + 1 - len(result))
        result.extend(chunk)
        if len(result) > MAX_BYTES:
            raise ValueError("Document too large")
    if decoder and (not decoder.eof or decoder.unused_data):
        raise ValueError("Invalid compressed document")
    return bytes(result)


class SafeFetcher:
    def __init__(self, client, *, resolver=public_addresses, sleeper=time.sleep):
        self.client = client
        self.resolver = resolver
        self.sleeper = sleeper

    def get(self, url, deadline):
        for attempt in range(3):
            try:
                return self._download(url, deadline)
            except (httpx.TransportError, OSError, httpx.HTTPStatusError) as exc:
                if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code < 500:
                    raise
                if attempt == 2:
                    raise
                delay = 2 ** (attempt + 1)
                if check_time(deadline) <= delay:
                    raise TimeoutError("BMKG deadline") from exc
                self.sleeper(delay)

    def _download(self, url, deadline):
        for hop in range(4):
            check_time(deadline)
            request_end = min(time.monotonic() + 15, deadline)
            target = checked_url(url)
            addresses = [ipaddress.ip_address(value) for value in self.resolver(target.host)]
            if not addresses or any(
                not ip.is_global or ip.is_multicast or ip.is_reserved for ip in addresses
            ):
                raise ValueError("Non-public BMKG address")
            with self.client.stream(
                "GET",
                target,
                follow_redirects=False,
                timeout=check_time(request_end),
                headers={"Accept-Encoding": "gzip, identity"},
                extensions={"bmkg_ip": str(addresses[0])},
            ) as response:
                check_time(request_end)
                if response.is_redirect:
                    if hop == 3 or "location" not in response.headers:
                        raise ValueError("Invalid redirect")
                    url = urljoin(str(target), response.headers["location"])
                    continue
                response.raise_for_status()
                body = bounded_body(response, request_end)
                check_time(request_end)
                return body


@contextmanager
def open_fetcher(*, transport=None, **kwargs):
    with httpx.Client(transport=transport or PublicTransport(), trust_env=False) as client:
        yield SafeFetcher(client, **kwargs)
