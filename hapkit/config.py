"""Local settings: environment variables first, then hapkit.local.env in the repository root (gitignored).

hapkit.local.env holds KEY=VALUE lines (no quoting, '#' comments); see hapkit.local.env.example."""
from __future__ import annotations

import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LOCAL_ENV = os.path.join(ROOT, "hapkit.local.env")


def _file() -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        with open(LOCAL_ENV) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    out[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return out


def get(key: str, default: str | None = None) -> str | None:
    return os.environ.get(key) or _file().get(key) or default
