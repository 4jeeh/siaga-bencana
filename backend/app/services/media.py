from dataclasses import dataclass
from hashlib import sha256
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

from app.core.errors import ApiError

MAX_PHOTO_BYTES = 2_097_152
MAX_INPUT_DIMENSION = 4096
MAX_INPUT_PIXELS = 16_000_000
MAX_OUTPUT_DIMENSION = 1024
JPEG_QUALITY = 75


@dataclass(frozen=True)
class SanitizedPhoto:
    data: bytes
    sha256: str
    width: int
    height: int
    size_bytes: int


def _check_bytes(size: int) -> None:
    if size > MAX_PHOTO_BYTES:
        raise ApiError(
            413,
            "REQUEST_TOO_LARGE",
            "Foto terlalu besar.",
            {
                "max_bytes": MAX_PHOTO_BYTES,
            },
        )


def sanitize_jpeg(raw: bytes, content_type: str) -> SanitizedPhoto:
    unsupported = ApiError(415, "UNSUPPORTED_MEDIA_TYPE", "Foto harus berformat JPEG.")
    invalid = ApiError(422, "VALIDATION_ERROR", "Foto tidak valid.")
    if (content_type or "").partition(";")[0].strip().lower() != "image/jpeg":
        raise unsupported
    if not raw:
        raise invalid
    _check_bytes(len(raw))
    if not raw.startswith(b"\xff\xd8\xff"):
        raise unsupported

    try:
        with Image.open(BytesIO(raw)) as img:
            if img.format != "JPEG":
                raise unsupported
            # Inspect the header before allocating pixels. Keep Pillow's global guard intact.
            if (
                max(img.size) > MAX_INPUT_DIMENSION
                or min(img.size) <= 0
                or img.width * img.height > MAX_INPUT_PIXELS
                or "A" in img.getbands()
            ):
                raise invalid
            img.load()
            clean = ImageOps.exif_transpose(img).convert("RGB")
        if max(clean.size) > MAX_OUTPUT_DIMENSION:
            clean.thumbnail((MAX_OUTPUT_DIMENSION, MAX_OUTPUT_DIMENSION), Image.Resampling.LANCZOS)
        clean.info.clear()
        output = BytesIO()
        clean.save(
            output,
            format="JPEG",
            quality=JPEG_QUALITY,
            subsampling=2,
            optimize=False,
            progressive=False,
        )
    except (
        UnidentifiedImageError,
        OSError,
        ValueError,
        SyntaxError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ):
        raise invalid from None
    data = output.getvalue()
    _check_bytes(len(data))
    return SanitizedPhoto(data, sha256(data).hexdigest(), clean.width, clean.height, len(data))
