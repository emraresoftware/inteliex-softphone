from __future__ import annotations

import argparse
import asyncio
import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import requests

from logger import get_logger

LOGGER = get_logger("dervis_github_haberlesme")

DEFAULT_API_BASE = "https://api.github.com"
DEFAULT_POLL_SECONDS = 8


@dataclass(frozen=True)
class GitHubConfig:
    owner: str
    repo: str
    token: str
    issue_number: int
    agent_name: str
    api_base: str = DEFAULT_API_BASE


class GitHubRelay:
    def __init__(self, config: GitHubConfig) -> None:
        self.config = config
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Bearer {config.token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": f"dervis-relay-{config.agent_name}",
            }
        )

    @classmethod
    def from_env(cls) -> "GitHubRelay":
        owner = os.getenv("DERGAH_GITHUB_OWNER", "").strip()
        repo = os.getenv("DERGAH_GITHUB_REPO", "").strip()
        token = os.getenv("DERGAH_GITHUB_TOKEN", "").strip()
        issue_raw = os.getenv("DERGAH_GITHUB_CHANNEL_ISSUE", "").strip()
        agent_name = os.getenv("DERGAH_NODE_NAME", "Dervis")
        api_base = os.getenv("DERGAH_GITHUB_API_BASE", DEFAULT_API_BASE).rstrip("/")

        if not owner or not repo or not token or not issue_raw:
            raise ValueError(
                "GitHub relay icin DERGAH_GITHUB_OWNER, DERGAH_GITHUB_REPO, "
                "DERGAH_GITHUB_TOKEN ve DERGAH_GITHUB_CHANNEL_ISSUE zorunlu"
            )

        issue_number = int(issue_raw)
        return cls(
            GitHubConfig(
                owner=owner,
                repo=repo,
                token=token,
                issue_number=issue_number,
                agent_name=agent_name,
                api_base=api_base,
            )
        )

    def _comments_url(self) -> str:
        c = self.config
        return f"{c.api_base}/repos/{c.owner}/{c.repo}/issues/{c.issue_number}/comments"

    def post_message(self, kind: str, content: str, meta: dict[str, Any] | None = None) -> dict[str, Any]:
        payload = {
            "ts_utc": datetime.now(timezone.utc).isoformat(),
            "agent": self.config.agent_name,
            "kind": kind,
            "content": content,
            "meta": meta or {},
        }
        body = "<!-- dervis-relay -->\n" + json.dumps(payload, ensure_ascii=False)
        response = self.session.post(self._comments_url(), json={"body": body}, timeout=30)
        response.raise_for_status()
        return response.json()

    def fetch_messages(self, since_id: int = 0, limit: int = 30) -> list[dict[str, Any]]:
        response = self.session.get(self._comments_url(), params={"per_page": min(limit, 100)}, timeout=30)
        response.raise_for_status()
        comments = response.json()
        results: list[dict[str, Any]] = []

        for item in comments:
            cid = int(item.get("id", 0) or 0)
            if cid <= since_id:
                continue
            body = str(item.get("body", ""))
            if "<!-- dervis-relay -->" not in body:
                continue
            json_part = body.split("\n", 1)[1] if "\n" in body else "{}"
            try:
                parsed = json.loads(json_part)
                parsed["comment_id"] = cid
                results.append(parsed)
            except Exception:
                continue

        results.sort(key=lambda x: int(x.get("comment_id", 0)))
        return results

    async def heartbeat_loop(self, interval_seconds: int = 60) -> None:
        LOGGER.info("GitHub heartbeat baslatildi", interval=interval_seconds)
        while True:
            try:
                await asyncio.to_thread(
                    self.post_message,
                    "heartbeat",
                    "alive",
                    {"interval_seconds": interval_seconds},
                )
            except Exception as exc:
                LOGGER.warning("Heartbeat gonderilemedi", detail=str(exc))
            await asyncio.sleep(interval_seconds)


async def _cmd_send(relay: GitHubRelay, args: argparse.Namespace) -> None:
    result = await asyncio.to_thread(relay.post_message, args.kind, args.content, {"source": "cli"})
    print(f"gonderildi: comment_id={result.get('id')}")


async def _cmd_poll(relay: GitHubRelay, args: argparse.Namespace) -> None:
    messages = await asyncio.to_thread(relay.fetch_messages, args.since_id, args.limit)
    for item in messages:
        print(json.dumps(item, ensure_ascii=False))
    print(f"toplam={len(messages)}")


async def _cmd_listen(relay: GitHubRelay, args: argparse.Namespace) -> None:
    since_id = args.since_id
    print(f"dinleme basladi: issue={relay.config.issue_number} poll={args.poll_seconds}s")
    while True:
        try:
            messages = await asyncio.to_thread(relay.fetch_messages, since_id, args.limit)
            for item in messages:
                cid = int(item.get("comment_id", 0) or 0)
                since_id = max(since_id, cid)
                print(json.dumps(item, ensure_ascii=False))
        except Exception as exc:
            LOGGER.warning("Dinleme hatasi", detail=str(exc))
        await asyncio.sleep(args.poll_seconds)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="GitHub issue comment tabanli dervis haberlesme araci")
    sub = parser.add_subparsers(dest="command", required=True)

    send = sub.add_parser("send", help="GitHub kanalina mesaj gonder")
    send.add_argument("--kind", default="message")
    send.add_argument("--content", required=True)

    poll = sub.add_parser("poll", help="Tek seferlik mesaj cek")
    poll.add_argument("--since-id", type=int, default=0)
    poll.add_argument("--limit", type=int, default=30)

    listen = sub.add_parser("listen", help="Surekli dinle")
    listen.add_argument("--since-id", type=int, default=0)
    listen.add_argument("--limit", type=int, default=30)
    listen.add_argument("--poll-seconds", type=int, default=DEFAULT_POLL_SECONDS)

    heartbeat = sub.add_parser("heartbeat", help="Periyodik heartbeat gonder")
    heartbeat.add_argument("--interval-seconds", type=int, default=60)

    return parser


async def _run() -> None:
    args = _build_parser().parse_args()
    relay = GitHubRelay.from_env()

    if args.command == "send":
        await _cmd_send(relay, args)
        return
    if args.command == "poll":
        await _cmd_poll(relay, args)
        return
    if args.command == "listen":
        await _cmd_listen(relay, args)
        return
    if args.command == "heartbeat":
        await relay.heartbeat_loop(args.interval_seconds)
        return

    raise ValueError(f"bilinmeyen komut: {args.command}")


if __name__ == "__main__":
    asyncio.run(_run())
