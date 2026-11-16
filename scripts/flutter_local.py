"""Run cached Flutter tooling without the batch launcher's Git commands."""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sdk = ROOT / ".tooling/flutter"
snapshot = sdk / "bin/cache/flutter_tools.snapshot"
if not snapshot.exists():
    sys.exit("Missing .tooling/flutter SDK copy; see backend/README.md.")
environment = {
    **os.environ,
    "FLUTTER_ROOT": str(sdk),
    "CI": "true",
    "PUB_CACHE": str(ROOT / ".tooling/pub-cache"),
}
sys.exit(
    subprocess.call(
        [
            str(sdk / "bin/cache/dart-sdk/bin/dart.exe"),
            str(snapshot),
            "--no-version-check",
            "--suppress-analytics",
            *sys.argv[1:],
        ],
        env=environment,
    )
)
