"""
Dervişler Arası Mesajlaşma Sistemi — SQLite Backend
2026-03-30: NDJSON → SQLite migration

Avantajları:
- ACID uyumlu (atomik işlemler)
- Mesaj kaybı riski yok
- Concurrent erişim güvenli
- İndeksleme ile hızlı sorgulama
"""
from __future__ import annotations

import json
import uuid
import sqlite3
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
AGENTS_DIR = ROOT / "agents"
AGENTS_JSON_PATH = AGENTS_DIR / "agents.json"
DB_PATH = AGENTS_DIR / "messages.db"

# Thread-safe lock for concurrent database access
_db_lock = threading.Lock()


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _get_db_connection() -> sqlite3.Connection:
    """Thread-safe database connection."""
    conn = sqlite3.connect(str(DB_PATH), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def _get_db():
    """Context manager for database operations with auto-commit/rollback."""
    with _db_lock:
        conn = _get_db_connection()
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()


def _init_db() -> None:
    """Initialize SQLite database schema (idempotent)."""
    with _get_db() as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                ts TEXT NOT NULL,
                event TEXT NOT NULL,
                kind TEXT NOT NULL DEFAULT 'note',
                sender TEXT NOT NULL,
                recipient TEXT,
                content TEXT NOT NULL,
                acked_by TEXT,
                acked_at TEXT,
                ack_note TEXT
            );
            
            CREATE INDEX IF NOT EXISTS idx_messages_recipient ON messages(recipient);
            CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender);
            CREATE INDEX IF NOT EXISTS idx_messages_event ON messages(event);
            CREATE INDEX IF NOT EXISTS idx_messages_ts ON messages(ts DESC);
            
            CREATE TABLE IF NOT EXISTS agent_status (
                agent_id TEXT PRIMARY KEY,
                last_seen TEXT,
                current_task TEXT,
                status TEXT DEFAULT 'idle'
            );
        """)


# Schema initialization on module import
_init_db()


def _load_agents() -> dict[str, dict[str, Any]]:
    """Load agent configuration from agents.json."""
    with open(AGENTS_JSON_PATH, encoding="utf-8") as f:
        data = json.load(f)
    agents = data.get("agents", [])
    return {str(agent.get("id", "")).strip(): agent for agent in agents if agent.get("id")}


def _resolve_agent_workspace(agent_id: str, agent: dict[str, Any]) -> Path:
    """Resolve agent workspace directory."""
    raw_path = str(agent.get("path", "")).strip()
    if raw_path:
        p = Path(raw_path)
        if not p.is_absolute():
            p = ROOT / p
        return p
    return AGENTS_DIR / "workspaces" / agent_id


def _append_inbox_md(agent_id: str, sender: str, content: str, message_id: str, ts: str) -> None:
    """Append message to agent's INBOX.md for visual reference (mirror to SQLite)."""
    agents = _load_agents()
    agent = agents.get(agent_id)
    if agent is None:
        ws_dir = AGENTS_DIR / "workspaces" / agent_id
    else:
        ws_dir = _resolve_agent_workspace(agent_id, agent)
    
    inbox_path = ws_dir / "INBOX.md"
    ws_dir.mkdir(parents=True, exist_ok=True)
    
    block = [
        "",
        f"## {ts} | {message_id}",
        f"from: {sender}",
        "",
        content.strip(),
        "",
        "- durum: okunmadi",
        "",
    ]
    
    if not inbox_path.exists():
        header = [
            f"# INBOX — {agent_id}",
            "",
            "Ajanlar arasi kapali devre mesaj kutusu.",
            "Durum guncelleme icin: dervis mesaj okundu --agent <id> --id <mesaj_id>",
            "",
        ]
        inbox_path.write_text("\n".join(header + block), encoding="utf-8")
    else:
        with inbox_path.open("a", encoding="utf-8") as f:
            f.write("\n".join(block))


def send_message(sender: str, recipient: str, content: str, *, kind: str = "note") -> str:
    """Send a message from one agent to another.
    
    Args:
        sender: Sender agent ID
        recipient: Recipient agent ID
        content: Message content
        kind: Message type (note, broadcast, auto_coordinator)
    
    Returns:
        Message ID
    
    Raises:
        ValueError: If sender or recipient is not in agents.json
    """
    agents = _load_agents()
    if sender not in agents:
        raise ValueError(f"Bilinmeyen gonderen ajan: {sender}")
    if recipient not in agents:
        raise ValueError(f"Bilinmeyen hedef ajan: {recipient}")
    
    message_id = f"msg-{uuid.uuid4().hex[:10]}"
    ts = _now_iso()
    
    # Insert into SQLite (ACID guaranteed)
    with _get_db() as conn:
        conn.execute(
            """
            INSERT INTO messages (id, ts, event, kind, sender, recipient, content)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (message_id, ts, "message", kind, sender, recipient, content.strip()),
        )
    
    # Also update INBOX.md for visual reference
    _append_inbox_md(recipient, sender, content, message_id, ts)
    
    return message_id


def broadcast_message(sender: str, content: str, *, kind: str = "broadcast") -> list[str]:
    """Broadcast a message to all agents except sender.
    
    Args:
        sender: Sender agent ID
        content: Message content
        kind: Message type
    
    Returns:
        List of message IDs sent
    """
    agents = _load_agents()
    if sender not in agents:
        raise ValueError(f"Bilinmeyen gonderen ajan: {sender}")
    
    return [
        send_message(sender, recipient, content, kind=kind)
        for recipient in agents
        if recipient != sender
    ]


def list_inbox(
    agent_id: str,
    *,
    limit: int = 20,
    include_acked: bool = False,
) -> list[dict[str, Any]]:
    """List inbox messages for an agent.
    
    Args:
        agent_id: Agent ID
        limit: Maximum number of messages to return
        include_acked: Include already acknowledged messages
    
    Returns:
        List of message dictionaries
    
    Raises:
        ValueError: If agent_id is not in agents.json
    """
    agents = _load_agents()
    if agent_id not in agents:
        raise ValueError(f"Bilinmeyen ajan: {agent_id}")
    
    with _get_db() as conn:
        # Get unacked messages
        rows = conn.execute(
            """
            SELECT m.*, a.acked_at IS NOT NULL as is_acked
            FROM messages m
            LEFT JOIN agent_status a ON m.id = a.acked_by
            WHERE m.recipient = ? AND m.event = 'message'
            ORDER BY m.ts DESC
            LIMIT ?
            """,
            (agent_id, limit * 2),  # Fetch more to filter
        ).fetchall()
    
    messages: list[dict[str, Any]] = []
    for row in rows:
        is_acked = bool(row["acked_by"])
        if not include_acked and is_acked:
            continue
        messages.append({
            "id": row["id"],
            "ts": row["ts"],
            "event": row["event"],
            "kind": row["kind"],
            "from": row["sender"],
            "to": row["recipient"],
            "content": row["content"],
            "acked": is_acked,
        })
        if len(messages) >= limit:
            break
    
    return messages


def ack_message(agent_id: str, message_id: str, note: str = "okundu") -> None:
    """Acknowledge a message.
    
    Args:
        agent_id: Agent ID acknowledging the message
        message_id: Message ID to acknowledge
        note: Optional acknowledgment note
    
    Raises:
        ValueError: If agent_id or message_id is invalid
    """
    agents = _load_agents()
    if agent_id not in agents:
        raise ValueError(f"Bilinmeyen ajan: {agent_id}")
    
    mid = message_id.strip()
    if not mid:
        raise ValueError("Mesaj id bos olamaz")
    
    ts = _now_iso()
    
    with _get_db() as conn:
        # Upsert acknowledgment
        conn.execute(
            """
            INSERT INTO agent_status (agent_id, last_seen, current_task, status)
            VALUES (?, ?, NULL, 'idle')
            ON CONFLICT(agent_id) DO UPDATE SET
                last_seen = excluded.last_seen,
                current_task = excluded.current_task,
                status = excluded.status
            """,
            (agent_id, ts),
        )
        
        # Store ack reference
        conn.execute(
            """
            INSERT INTO messages (id, ts, event, kind, sender, recipient, content, acked_by, acked_at, ack_note)
            VALUES (?, ?, 'ack', 'system', ?, ?, ?, ?, ?, ?)
            """,
            (f"ack-{uuid.uuid4().hex[:10]}", ts, agent_id, agent_id, mid, agent_id, ts, note.strip() or "okundu"),
        )


def update_agent_status(agent_id: str, status: str = "idle", task: str | None = None) -> None:
    """Update agent status in database.
    
    Args:
        agent_id: Agent ID
        status: Status string (idle, working, blocked, error)
        task: Current task ID (optional)
    """
    agents = _load_agents()
    if agent_id not in agents:
        raise ValueError(f"Bilinmeyen ajan: {agent_id}")
    
    ts = _now_iso()
    
    with _get_db() as conn:
        conn.execute(
            """
            INSERT INTO agent_status (agent_id, last_seen, current_task, status)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(agent_id) DO UPDATE SET
                last_seen = excluded.last_seen,
                current_task = COALESCE(excluded.current_task, current_task),
                status = excluded.status
            """,
            (agent_id, ts, task, status),
        )


def get_all_agent_status() -> list[dict[str, Any]]:
    """Get status of all agents.
    
    Returns:
        List of agent status dictionaries
    """
    with _get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM agent_status ORDER BY last_seen DESC"
        ).fetchall()
    
    return [dict(row) for row in rows]


def get_active_agents(minutes: int = 5) -> list[dict[str, Any]]:
    """Get agents active in the last N minutes.
    
    Args:
        minutes: Time window in minutes
    
    Returns:
        List of recently active agent status dictionaries
    """
    import time
    
    cutoff = time.time() - (minutes * 60)
    cutoff_iso = datetime.fromtimestamp(cutoff, tz=timezone.utc).isoformat()
    
    with _get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM agent_status WHERE last_seen > ? ORDER BY last_seen DESC",
            (cutoff_iso,),
        ).fetchall()
    
    return [dict(row) for row in rows]


def get_agent_status(agent_id: str) -> dict[str, Any] | None:
    """Get agent status from database.
    
    Returns:
        Status dictionary or None if not found
    """
    with _get_db() as conn:
        row = conn.execute(
            "SELECT * FROM agent_status WHERE agent_id = ?",
            (agent_id,),
        ).fetchone()
    
    if row is None:
        return None
    
    return dict(row)


def get_message_stats() -> dict[str, int]:
    """Get message statistics.
    
    Returns:
        Dictionary with total messages, unread count, etc.
    """
    with _get_db() as conn:
        total = conn.execute(
            "SELECT COUNT(*) FROM messages WHERE event = 'message'"
        ).fetchone()[0]
        
        total_acks = conn.execute(
            "SELECT COUNT(*) FROM messages WHERE event = 'ack'"
        ).fetchone()[0]
        
        unread = conn.execute(
            """
            SELECT COUNT(*) FROM messages m
            WHERE m.event = 'message'
            AND NOT EXISTS (
                SELECT 1 FROM messages a
                WHERE a.event = 'ack'
                AND a.content = m.id
            )
            """
        ).fetchone()[0]
    
    return {
        "total_messages": total,
        "total_acks": total_acks,
        "unread": unread,
    }


def migrate_from_ndjson(ndjson_path: Path | None = None) -> dict[str, int]:
    """Migrate messages from NDJSON format to SQLite.
    
    Args:
        ndjson_path: Path to NDJSON file (defaults to messages.ndjson)
    
    Returns:
        Migration stats {"imported": int, "skipped": int, "errors": int}
    """
    import_errors: int = 0
    import_count: int = 0
    skip_count: int = 0
    
    if ndjson_path is None:
        ndjson_path = AGENTS_DIR / "messages.ndjson"
    
    if not ndjson_path.exists():
        return {"imported": 0, "skipped": 0, "errors": 0, "note": "No NDJSON file found"}
    
    with open(ndjson_path, encoding="utf-8") as f:
        lines = f.readlines()
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
        
        try:
            data = json.loads(line)
            
            # Check if already imported (by ID)
            with _get_db() as conn:
                existing = conn.execute(
                    "SELECT 1 FROM messages WHERE id = ?",
                    (data.get("id", ""),),
                ).fetchone()
                
                if existing:
                    skip_count += 1
                    continue
            
            with _get_db() as conn:
                conn.execute(
                    """
                    INSERT INTO messages (id, ts, event, kind, sender, recipient, content)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        data.get("id", ""),
                        data.get("ts", ""),
                        data.get("event", "message"),
                        data.get("kind", "note"),
                        data.get("from", ""),
                        data.get("to", ""),
                        data.get("content", ""),
                    ),
                )
                import_count += 1
                
        except Exception:
            import_errors += 1
    
    return {
        "imported": import_count,
        "skipped": skip_count,
        "errors": import_errors,
        "note": f"Migrated from {ndjson_path}",
    }
