from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any

import dervis_mesajlasma as dm


QUESTION_HINTS = [
    "?",
    "onay",
    "izin",
    "devam",
    "karar",
    "nasil",
    "ne yapalim",
    "bekliyorum",
]

BLOCKER_HINTS = [
    "blokaj",
    "blocked",
    "takildim",
    "hata",
    "patladi",
    "calismiyor",
    "acil",
]


@dataclass
class ProcessStats:
    checked: int = 0
    acked: int = 0
    replied: int = 0


def _normalize(text: str) -> str:
    return (text or "").strip().lower()


def _contains_any(text: str, hints: list[str]) -> bool:
    low = _normalize(text)
    return any(h in low for h in hints)


def _build_reply(content: str) -> str:
    low = _normalize(content)

    if _contains_any(low, BLOCKER_HINTS):
        return (
            "Koordinator otomatik yanit: Blokaj kaydi alindi. "
            "Faz kapsamindan cikmadan gecici cozumle devam et; "
            "kritikse en kisa raporla geri don."
        )

    if _contains_any(low, QUESTION_HINTS):
        return (
            "Koordinator otomatik yanit: Onay verildi. "
            "Tanimli gorev kapsami icinde otonom ilerle, "
            "sadece kritik sapmada kisa durum raporu gonder."
        )

    return ""


def process_once(agent_id: str, *, limit: int = 20, dry_run: bool = False) -> ProcessStats:
    rows = dm.list_inbox(agent_id, limit=max(1, limit), include_acked=False)
    stats = ProcessStats(checked=len(rows))

    # Eski -> yeni sirada isleyelim
    for row in reversed(rows):
        msg_id = str(row.get("id", "")).strip()
        sender = str(row.get("from", "")).strip()
        content = str(row.get("content", "")).strip()

        if not msg_id:
            continue
        if sender == agent_id:
            if not dry_run:
                dm.ack_message(agent_id, msg_id, "self-message")
            stats.acked += 1
            continue

        reply = _build_reply(content)
        if reply and sender:
            if not dry_run:
                dm.send_message(agent_id, sender, reply, kind="auto_coordinator")
            stats.replied += 1

        if not dry_run:
            dm.ack_message(agent_id, msg_id, "auto-processed")
        stats.acked += 1

    return stats


def run_loop(
    agent_id: str,
    *,
    interval_sec: int = 20,
    limit: int = 40,
    dry_run: bool = False,
    stop_event: "threading.Event | None" = None,
) -> None:
    import threading as _threading
    from datetime import datetime, timezone

    _stop = stop_event if stop_event is not None else _threading.Event()
    _err_log = Path(__file__).resolve().parents[1] / "data" / "koordinator_errors.log"

    while not _stop.is_set():
        try:
            process_once(agent_id, limit=limit, dry_run=dry_run)
        except Exception as exc:
            # Kritik hataları sessizce yutma, logla
            ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            err_msg = f"[{ts}] ERROR | agent={agent_id} | {type(exc).__name__}: {exc}\n"
            try:
                _err_log.parent.mkdir(parents=True, exist_ok=True)
                _err_log.write_text(_err_log.read_text() + err_msg, encoding="utf-8")
            except Exception:
                pass  # Log yazılamazsa yine de devam et
        _stop.wait(timeout=max(3, interval_sec))
