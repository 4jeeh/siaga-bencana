import base64
import hmac
import os
import re
from contextlib import nullcontext
from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import NamedTemporaryFile
from urllib.parse import quote
from uuid import UUID, uuid4

import httpx

from app.core.config import Settings
from app.core.errors import ApiError

OBJECT_KEY = re.compile(r"[0-9a-f-]{36}\.jpg")


def generate_object_key() -> str:
    return f"{uuid4()}.jpg"


def validate_object_key(key: str) -> None:
    if not isinstance(key, str) or not OBJECT_KEY.fullmatch(key):
        raise ApiError(422, "VALIDATION_ERROR", "Kunci foto tidak valid.")


def _unavailable() -> ApiError:
    return ApiError(503, "SERVICE_UNAVAILABLE", "Penyimpanan foto belum tersedia.")


def _expiry(now: datetime | None, ttl_seconds: int) -> datetime:
    if type(ttl_seconds) is not int or not 1 <= ttl_seconds <= 300:
        raise ApiError(422, "VALIDATION_ERROR", "Masa berlaku URL tidak valid.")
    return (now or datetime.now(UTC)).astimezone(UTC).replace(microsecond=0) + timedelta(
        seconds=ttl_seconds
    )


def _photo_path(report_id: UUID) -> str:
    return f"/api/v1/media/reports/{UUID(str(report_id))}/photo"


def _signature(path, object_key, expires, settings):
    namespace = f"{settings.app_mode}:{settings.storage_backend}"
    payload = f"GET\n{path}\n{object_key}\n{expires}\n{namespace}".encode()
    secret = settings.media_signing_secret.get_secret_value().encode()
    return base64.urlsafe_b64encode(hmac.digest(secret, payload, "sha256")).rstrip(b"=").decode()


def sign_local_photo_url(base_url, report_id, object_key, settings, *, now=None, ttl_seconds=300):
    validate_object_key(object_key)
    path = _photo_path(report_id)
    expiry = _expiry(now, ttl_seconds)
    expires = int(expiry.timestamp())
    signature = _signature(path, object_key, expires, settings)
    url = f"{str(base_url).rstrip('/')}{path}?expires={expires}&signature={signature}"
    return url, expiry, ttl_seconds


def verify_local_photo_signature(
    report_id, object_key, expires, signature, settings, *, now=None
) -> bool:
    current = int((now or datetime.now(UTC)).timestamp())
    if (
        type(expires) is not int
        or not current < expires <= current + 300
        or not isinstance(signature, str)
        or not signature.isascii()
    ):
        return False
    try:
        validate_object_key(object_key)
        expected = _signature(_photo_path(report_id), object_key, expires, settings)
    except ApiError, ValueError:
        return False
    return hmac.compare_digest(expected, signature)


class LocalStorageAdapter:
    def __init__(self, settings: Settings):
        self.settings = settings

    def _root(self) -> Path:
        root = self.settings.storage_root
        if root.resolve() != root:
            raise _unavailable()
        return root

    def _path(self, key: str) -> Path:
        validate_object_key(key)
        path = self._root() / key
        if path.resolve() != path or path.is_symlink():
            raise ApiError(403, "FORBIDDEN", "Akses foto ditolak.")
        return path

    def put_bytes(self, object_key, data):
        temp = None
        try:
            path = self._path(object_key)
            path.parent.mkdir(parents=True, exist_ok=True)
            try:
                with NamedTemporaryFile(dir=path.parent, delete=False) as output:
                    temp = Path(output.name)
                    output.write(data)
                os.replace(temp, path)
            finally:
                if temp is not None:
                    temp.unlink(missing_ok=True)
        except OSError:
            raise _unavailable() from None

    def get_bytes(self, object_key):
        try:
            return self._path(object_key).read_bytes()
        except FileNotFoundError:
            raise
        except OSError:
            raise _unavailable() from None

    def delete_object(self, object_key):
        try:
            self._path(object_key).unlink(missing_ok=True)
        except OSError:
            raise _unavailable() from None

    def list_objects(self) -> list[tuple[str, datetime]]:
        objects = []
        try:
            root = self._root()
            if root.exists():
                for path in root.iterdir():
                    if OBJECT_KEY.fullmatch(path.name) and not path.is_symlink() and path.is_file():
                        try:
                            modified = self._path(path.name).stat().st_mtime
                        except FileNotFoundError:
                            continue
                        objects.append((path.name, datetime.fromtimestamp(modified, UTC)))
        except OSError:
            raise _unavailable() from None
        return objects

    def create_signed_url(
        self, request_base_url, report_id, object_key, *, now=None, ttl_seconds=300
    ):
        return sign_local_photo_url(
            request_base_url, report_id, object_key, self.settings, now=now, ttl_seconds=ttl_seconds
        )


class SupabaseStorageAdapter:
    def __init__(self, settings: Settings, client_factory=None):
        self.settings = settings
        self.client_factory = client_factory

    @property
    def is_configured(self) -> bool:
        try:
            base = httpx.URL(self.settings.supabase_url)
        except httpx.InvalidURL:
            return False
        return bool(
            base.scheme in {"https", "http"}
            and base.host
            and self.settings.storage_bucket.strip()
            and self.settings.supabase_service_key.get_secret_value().strip()
        )

    @property
    def _bucket(self):
        return quote(self.settings.storage_bucket, safe="")

    def _request(self, method, path, *, headers=None, **kwargs):
        if not self.is_configured:
            raise _unavailable()
        secret = self.settings.supabase_service_key.get_secret_value()
        auth = {"apikey": secret, "Authorization": f"Bearer {secret}"}
        url = self.settings.supabase_url.rstrip("/") + "/storage/v1" + path
        factory = self.client_factory
        try:
            if isinstance(factory, httpx.Client):
                context = nullcontext(factory)
            elif isinstance(factory, httpx.BaseTransport):
                context = httpx.Client(transport=factory, timeout=15, trust_env=False)
            else:
                context = (factory or httpx.Client)(timeout=15, trust_env=False)
            with context as client:
                return client.request(method, url, headers=auth | (headers or {}), **kwargs)
        except httpx.HTTPError, httpx.InvalidURL, ValueError:
            raise _unavailable() from None

    def check_ready(self) -> bool:
        try:
            response = self._request("GET", f"/bucket/{self._bucket}")
            if response.status_code == 200:
                bucket = response.json()
                return isinstance(bucket, dict) and bucket.get("public") is False
        except ApiError, ValueError:
            pass
        return False

    def put_bytes(self, object_key, data):
        validate_object_key(object_key)
        response = self._request(
            "POST",
            f"/object/{self._bucket}/{object_key}",
            headers={"content-type": "image/jpeg", "x-upsert": "false"},
            content=data,
        )
        if not response.is_success:
            raise _unavailable()

    def create_signed_url(
        self, request_base_url, report_id, object_key, *, now=None, ttl_seconds=300
    ):
        validate_object_key(object_key)
        expiry = _expiry(now, ttl_seconds)
        response = self._request(
            "POST", f"/object/sign/{self._bucket}/{object_key}", json={"expiresIn": ttl_seconds}
        )
        if not response.is_success:
            raise _unavailable()
        try:
            signed = response.json()["signedURL"]
            if not isinstance(signed, str) or not signed:
                raise ValueError
            if not httpx.URL(signed).scheme and not signed.startswith("//"):
                signed = (
                    self.settings.supabase_url.rstrip("/") + "/storage/v1/" + signed.lstrip("/")
                )
            url = httpx.URL(signed)
            if not url.host or url.scheme not in {"https", "http"}:
                raise ValueError
        except KeyError, TypeError, ValueError, httpx.InvalidURL:
            raise _unavailable() from None
        return signed, expiry, ttl_seconds

    def delete_object(self, object_key):
        validate_object_key(object_key)
        response = self._request("DELETE", f"/object/{self._bucket}/{object_key}")
        if not response.is_success and response.status_code != 404:
            raise _unavailable()

    def list_objects(self) -> list[tuple[str, datetime]]:
        objects = []
        offset = 0
        while True:
            response = self._request(
                "POST",
                f"/object/list/{self._bucket}",
                json={
                    "prefix": "",
                    "limit": 100,
                    "offset": offset,
                    "sortBy": {"column": "name", "order": "asc"},
                },
            )
            if not response.is_success:
                raise _unavailable()
            try:
                page = response.json()
                if not isinstance(page, list):
                    raise ValueError
                for entry in page:
                    name = entry["name"]
                    if OBJECT_KEY.fullmatch(name):
                        created = datetime.fromisoformat(entry["created_at"])
                        if created.tzinfo is None:
                            raise ValueError
                        objects.append((name, created.astimezone(UTC)))
            except TypeError, KeyError, ValueError:
                raise _unavailable() from None
            if len(page) < 100:
                return objects
            offset += len(page)


def build_storage_adapter(settings: Settings) -> LocalStorageAdapter | SupabaseStorageAdapter:
    if settings.storage_backend == "supabase":
        return SupabaseStorageAdapter(settings)
    return LocalStorageAdapter(settings)
