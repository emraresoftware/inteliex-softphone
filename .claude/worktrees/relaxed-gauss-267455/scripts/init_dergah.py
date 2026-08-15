from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

from logger import get_logger

ROOT_DIR = Path(__file__).resolve().parents[1]
PROJECTS_DIR = ROOT_DIR / "projects"
SCRIPTS_DIR = ROOT_DIR / "scripts"
DATA_DIR = ROOT_DIR / "data"
LEDGER_PATH = DATA_DIR / "dergah_defteri.json"
LOG_PATH = DATA_DIR / "islem_gunlugu.log"

LOGGER = get_logger("init_dergah")


def _default_ledger() -> dict[str, object]:
    return {
        "meta": {
            "olusturulma_zamani_utc": datetime.now(timezone.utc).isoformat(),
            "surum": "1.0",
            "aciklama": "Dergah proje tescil defteri",
        },
        "projeler": [],
    }


async def _ensure_directories() -> None:
    for path in [PROJECTS_DIR, SCRIPTS_DIR, DATA_DIR]:
        await asyncio.to_thread(path.mkdir, parents=True, exist_ok=True)
        LOGGER.success("Dizin hazir", path=str(path))


async def _ensure_files() -> None:
    if not LEDGER_PATH.exists():
        payload = _default_ledger()
        await asyncio.to_thread(
            LEDGER_PATH.write_text,
            json.dumps(payload, ensure_ascii=False, indent=2),
            "utf-8",
        )
        LOGGER.success("Varsayilan defter olusturuldu", path=str(LEDGER_PATH))
    else:
        LOGGER.info("Defter zaten mevcut", path=str(LEDGER_PATH))

    if not LOG_PATH.exists():
        await asyncio.to_thread(LOG_PATH.write_text, "", "utf-8")
        LOGGER.success("Islem gunlugu olusturuldu", path=str(LOG_PATH))
    else:
        LOGGER.info("Islem gunlugu zaten mevcut", path=str(LOG_PATH))


async def init_dergah() -> None:
    LOGGER.info("Dergah init basladi", root=str(ROOT_DIR))
    await _ensure_directories()
    await _ensure_files()
    LOGGER.success("Dergah init tamamlandi")


if __name__ == "__main__":
    asyncio.run(init_dergah())
