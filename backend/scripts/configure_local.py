"""Generate ignored local .env once, never print secrets or overwrite existing config."""

import secrets
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


if __name__ == "__main__":
    example = (ROOT / ".env.example").read_text(encoding="utf-8")
    example = example.replace("JWT_SECRET=\n", f"JWT_SECRET={secrets.token_urlsafe(48)}\n")
    example = example.replace(
        "MEDIA_SIGNING_SECRET=\n", f"MEDIA_SIGNING_SECRET={secrets.token_urlsafe(48)}\n"
    )
    try:
        with (ROOT / ".env").open("x", encoding="utf-8") as output:
            output.write(example)
    except FileExistsError:
        print("Existing .env preserved.")
    else:
        print("Ignored backend/.env generated with independent local secrets.")
