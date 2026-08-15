from __future__ import annotations

import argparse
import asyncio
import contextlib

from dervis_operator import dervis_dongusu
from dervis_haberlesme_github import GitHubRelay
from init_dergah import init_dergah
from logger import get_logger
from tescil_merasimi import tescil_baslat

LOGGER = get_logger("dergah_orkestrator")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Dergah sistemi icin init + tescil + operator asamalarini tek komutta calistirir."
    )
    parser.add_argument(
        "--operator",
        action="store_true",
        help="Tescil sonrasinda dervis operator dongusunu da baslat.",
    )
    parser.add_argument(
        "--github-announce",
        action="store_true",
        help="GitHub relay kanalina baslangic/bitis duyurusu gonder.",
    )
    parser.add_argument(
        "--github-heartbeat",
        action="store_true",
        help="GitHub relay kanalina surekli heartbeat gonder.",
    )
    return parser


async def _run_pipeline(start_operator: bool, github_announce: bool, github_heartbeat: bool) -> None:
    LOGGER.info("Orkestrasyon basladi")
    relay: GitHubRelay | None = None
    hb_task: asyncio.Task[None] | None = None

    if github_announce or github_heartbeat:
        try:
            relay = GitHubRelay.from_env()
            LOGGER.success("GitHub relay aktif", issue=relay.config.issue_number, repo=f"{relay.config.owner}/{relay.config.repo}")
        except Exception as exc:
            LOGGER.warning("GitHub relay baslatilamadi", detail=str(exc))

    if relay and github_announce:
        try:
            await asyncio.to_thread(relay.post_message, "orchestrator", "pipeline_started", {"operator": start_operator})
        except Exception as exc:
            LOGGER.warning("GitHub baslangic duyurusu gonderilemedi", detail=str(exc))

    if relay and github_heartbeat:
        hb_task = asyncio.create_task(relay.heartbeat_loop(60))

    LOGGER.info("Asama 1/3: Init")
    await init_dergah()

    LOGGER.info("Asama 2/3: Tescil")
    await tescil_baslat()

    if start_operator:
        LOGGER.info("Asama 3/3: Operator dongusu")
        await dervis_dongusu()
    else:
        LOGGER.info("Asama 3/3 atlandi", reason="--operator verilmedi")

    if relay and github_announce:
        try:
            await asyncio.to_thread(relay.post_message, "orchestrator", "pipeline_completed", {"operator": start_operator})
        except Exception as exc:
            LOGGER.warning("GitHub bitis duyurusu gonderilemedi", detail=str(exc))

    if hb_task:
        hb_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await hb_task

    LOGGER.success("Orkestrasyon tamamlandi")


def main() -> None:
    args = _build_parser().parse_args()
    asyncio.run(
        _run_pipeline(
            start_operator=args.operator,
            github_announce=args.github_announce,
            github_heartbeat=args.github_heartbeat,
        )
    )


if __name__ == "__main__":
    main()
