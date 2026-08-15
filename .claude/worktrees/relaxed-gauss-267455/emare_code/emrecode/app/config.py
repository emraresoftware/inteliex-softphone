"""Uygulama ayarlari (.env destekli, hafif parser)."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os


def _load_dotenv() -> None:
    env_file = Path(__file__).resolve().parents[1] / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


_load_dotenv()


@dataclass(frozen=True)
class Settings:
    hub_url: str = os.getenv("HUB_URL", "http://127.0.0.1:9860")
    hub_token_file: str = os.getenv("HUB_TOKEN_FILE", str(Path.home() / ".dervish-fleet" / ".fleet-token"))
    db_url: str = os.getenv("DB_URL", "sqlite+aiosqlite:///./emrecode.db")
    db_auto_create: bool = os.getenv("DB_AUTO_CREATE", "true").lower() in {"1", "true", "yes", "on"}
    listen_host: str = os.getenv("LISTEN_HOST", "127.0.0.1")
    listen_port: int = int(os.getenv("LISTEN_PORT", "9870"))
    dev_mode: bool = os.getenv("DEV_MODE", "true").lower() in {"1", "true", "yes", "on"}
    ollama_host: str = os.getenv("OLLAMA_HOST", "http://ollama:11434")


settings = Settings()
