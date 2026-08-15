from __future__ import annotations

import asyncio
import json
import os
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from logger import get_logger
from llm_bridge import chat, get_default_model_name

MODEL_NAME = get_default_model_name()
ROOT_DIR = Path(__file__).resolve().parents[1]
PROJECTS_DIR = ROOT_DIR / "projects"
LEDGER_PATH = ROOT_DIR / "data" / "dergah_defteri.json"
MAX_FILES_PER_PROJECT = 40
CONCURRENCY = 6

LOGGER = get_logger("tescil_merasimi")


@dataclass
class LedgerEntry:
    proje_adi: str
    teknoloji: str
    durum: str
    vazife: str


def _collect_project_fingerprint(project_path: Path) -> dict[str, Any]:
    file_names: list[str] = []
    extensions: dict[str, int] = {}
    ignored = {".git", "node_modules", ".venv", "__pycache__", ".idea", ".vscode"}

    for root_str, dirs, files in os.walk(project_path, topdown=True):
        root = Path(root_str)
        dirs[:] = [d for d in dirs if d not in ignored]
        for file_name in files:
            rel_path = (root / file_name).relative_to(project_path)
            file_names.append(str(rel_path))
            ext = (root / file_name).suffix.lower() or "<no_ext>"
            extensions[ext] = extensions.get(ext, 0) + 1
            if len(file_names) >= MAX_FILES_PER_PROJECT:
                break
        if len(file_names) >= MAX_FILES_PER_PROJECT:
            break

    top_ext = sorted(extensions.items(), key=lambda x: x[1], reverse=True)[:6]
    return {
        "sample_files": file_names,
        "top_extensions": top_ext,
    }


def _parse_model_payload(payload: str, project_name: str) -> LedgerEntry:
    cleaned = payload.strip()
    if cleaned.startswith("```"):
        lines = [line for line in cleaned.splitlines() if not line.strip().startswith("```")]
        cleaned = "\n".join(lines).strip()

    try:
        parsed = json.loads(cleaned)
        return LedgerEntry(
            proje_adi=project_name,
            teknoloji=str(parsed.get("teknoloji", "Belirsiz")),
            durum=str(parsed.get("durum", "Tescil Edildi")),
            vazife=str(parsed.get("vazife", "Ozet gorev tanimi bekleniyor")),
        )
    except json.JSONDecodeError:
        LOGGER.warning("Model JSON disi cevap verdi; varsayilan kayit yaziliyor", project=project_name)
        return LedgerEntry(
            proje_adi=project_name,
            teknoloji="Belirsiz",
            durum="Tescil Edildi",
            vazife=cleaned[:180] or "Model cevabi alinamadi",
        )


async def _analyze_project(project_path: Path, semaphore: asyncio.Semaphore) -> LedgerEntry:
    fingerprint = await asyncio.to_thread(_collect_project_fingerprint, project_path)
    project_name = project_path.name

    prompt = (
        "Asagidaki proje ozeti icin yalnizca JSON don. "
        "Format: {\"teknoloji\":\"...\",\"durum\":\"...\",\"vazife\":\"...\"}. "
        "Durum alani profesyonel olsun (Orn: Aktif Gelistirme, Bakim, Prototip).\n\n"
        f"Proje: {project_name}\n"
        f"Dosya ornekleri: {fingerprint['sample_files']}\n"
        f"Uzanti dagilimi: {fingerprint['top_extensions']}"
    )

    async with semaphore:
        LOGGER.info("Proje analizi basladi", project=project_name)
        response = await asyncio.to_thread(
            chat,
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": "Sen deneyimli bir teknik mimarsin."},
                {"role": "user", "content": prompt},
            ],
        )

    content = response.get("message", {}).get("content", "")
    entry = _parse_model_payload(content, project_name)
    LOGGER.success("Proje analizi tamamlandi", project=project_name)
    return entry


async def tescil_baslat() -> None:
    PROJECTS_DIR.mkdir(parents=True, exist_ok=True)
    LEDGER_PATH.parent.mkdir(parents=True, exist_ok=True)

    project_dirs = sorted([p for p in PROJECTS_DIR.iterdir() if p.is_dir()])
    if not project_dirs:
        LOGGER.warning("projects/ altinda tescil edilecek proje bulunamadi")

    semaphore = asyncio.Semaphore(CONCURRENCY)
    tasks = [_analyze_project(path, semaphore) for path in project_dirs]
    entries = await asyncio.gather(*tasks) if tasks else []

    payload = {
        "meta": {
            "olusturulma_zamani_utc": datetime.now(timezone.utc).isoformat(),
            "model": MODEL_NAME,
            "toplam_proje": len(entries),
        },
        "projeler": [asdict(entry) for entry in entries],
    }

    LEDGER_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    LOGGER.success("Dergah defteri guncellendi", path=str(LEDGER_PATH), total=len(entries))


if __name__ == "__main__":
    asyncio.run(tescil_baslat())