"""Disposable PostgreSQL cluster for localhost development and pytest.

Creates ``backend/.localdb/data`` (gitignored) with ``initdb`` and listens ONLY on
127.0.0.1. Loopback auth is ``trust`` because this cluster is throwaway dev/test
infrastructure; never reuse this configuration for Railway/Supabase.

Usage (from ``backend/``)::

    python scripts/local_pg.py start   # init on first run, then start on port 54329
    python scripts/local_pg.py stop
    python scripts/local_pg.py status
    python scripts/local_pg.py foreground  # Windows sandbox restricted-token fallback
"""

from __future__ import annotations

import argparse
import glob
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALDB = ROOT / ".localdb"
DATA_DIR = LOCALDB / "data"
LOG_FILE = LOCALDB / "postgres.log"


def find_pg_bin(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    pattern = r"C:\Program Files\PostgreSQL\*\bin\%s.exe" % name
    candidates = sorted(glob.glob(pattern), reverse=True)
    if candidates:
        return candidates[0]
    sys.exit(f"{name} not found. Install PostgreSQL 15+ or add its bin folder to PATH.")


def start(port: int) -> None:
    if status() == 0:
        print("Local PostgreSQL is already running.")
        return
    if not (DATA_DIR / "PG_VERSION").exists():
        LOCALDB.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [
                find_pg_bin("initdb"),
                "-D",
                str(DATA_DIR),
                "-U",
                "postgres",
                "--auth=trust",
                "-E",
                "UTF8",
                "--locale=C",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        with (DATA_DIR / "postgresql.conf").open("a", encoding="utf-8") as conf:
            conf.write(
                "\n# --- Siaga Bencana local dev overrides ---\n"
                "listen_addresses = '127.0.0.1'\n"
                f"port = {port}\n"
                "timezone = 'UTC'\n"
                "max_connections = 50\n"
            )
        print(f"Initialized disposable cluster at {DATA_DIR}")
    subprocess.run(
        [
            find_pg_bin("pg_ctl"),
            "-D",
            str(DATA_DIR),
            "-l",
            str(LOG_FILE),
            "-o",
            f"-h 127.0.0.1 -p {port}",
            "-w",
            "-t",
            "30",
            "start",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=40,
    )
    print(
        f"PostgreSQL on 127.0.0.1:{port} -> admin URL postgresql://postgres@127.0.0.1:{port}/postgres"
    )


def stop() -> None:
    if status() == 0:
        subprocess.run(
            [find_pg_bin("pg_ctl"), "-D", str(DATA_DIR), "-m", "fast", "-w", "stop"],
            check=True,
            timeout=40,
        )


def status() -> int:
    return subprocess.run(
        [find_pg_bin("pg_ctl"), "-D", str(DATA_DIR), "status"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
    ).returncode


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=["start", "stop", "status", "foreground"])
    parser.add_argument("--port", type=int, default=54329)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("Port must be between 1024 and 65535")
    if args.action == "start":
        start(args.port)
    elif args.action == "stop":
        stop()
    elif args.action == "status":
        print("running" if status() == 0 else "stopped")
    elif args.action == "foreground":
        if status() == 0:
            print("Local PostgreSQL is already running.")
            return
        if not (DATA_DIR / "PG_VERSION").exists():
            sys.exit("Initialize the cluster with start first.")
        # Same unprivileged process token; pg_ctl stop still performs orderly shutdown.
        subprocess.run(
            [find_pg_bin("postgres"), "-D", str(DATA_DIR), "-h", "127.0.0.1", "-p", str(args.port)],
            check=True,
        )


if __name__ == "__main__":
    main()
