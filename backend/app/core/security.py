from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
from pwdlib import PasswordHash

from app.core.errors import ApiError

password_hasher = PasswordHash.recommended()
# Equal-cost verification for missing accounts; not an account credential.
DUMMY_HASH = password_hasher.hash("non-account dummy verification")


def issue_token(user_id, settings):
    now = datetime.now(UTC).replace(microsecond=0)
    expires = now + timedelta(seconds=settings.jwt_ttl_seconds)
    claims = {
        "sub": str(user_id),
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": int(now.timestamp()),
        "exp": int(expires.timestamp()),
    }
    return jwt.encode(claims, settings.jwt_secret.get_secret_value(), algorithm="HS256"), expires


def decode_token(token, settings):
    try:
        claims = jwt.decode(
            token,
            settings.jwt_secret.get_secret_value(),
            algorithms=["HS256"],
            issuer=settings.jwt_issuer,
            audience=settings.jwt_audience,
            options={"require": ["sub", "iss", "aud", "iat", "exp"]},
        )
        if (
            type(claims["iat"]) is not int
            or type(claims["exp"]) is not int
            or claims["exp"] <= claims["iat"]
        ):
            raise ValueError("Invalid token times")
        return UUID(claims["sub"])
    except jwt.ExpiredSignatureError:
        raise ApiError(401, "TOKEN_EXPIRED", "Sesi berakhir, masuk kembali.") from None
    except jwt.InvalidTokenError, ValueError, TypeError, AttributeError:
        raise ApiError(401, "TOKEN_INVALID", "Sesi tidak valid, masuk kembali.") from None
