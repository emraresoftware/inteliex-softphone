from __future__ import annotations

import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

try:
  from dervis_mesajlasma import send_message
except Exception:
  try:
    from scripts.dervis_mesajlasma import send_message
  except Exception as exc:  # pragma: no cover - configuration/runtime fallback
    raise RuntimeError("scripts/dervis_mesajlasma.py import edilemedi") from exc

ROOT = Path(__file__).resolve().parents[1]
AGENTS_DIR = ROOT / "agents"
BACKLOG_PATH = AGENTS_DIR / "backlog.json"
AGENTS_PATH = AGENTS_DIR / "agents.json"
MESSAGES_PATH = AGENTS_DIR / "messages.ndjson"
HANDOFFS_PATH = AGENTS_DIR / "handoffs.ndjson"
DISPATCH_PATH = AGENTS_DIR / "dispatch.js"


app = FastAPI(title="Dervis Dashboard", version="0.1.0")


class DispatchRequest(BaseModel):
    all: bool = False
    role: str | None = None
    sprint: str | None = None
    dry_run: bool = False


class MessageRequest(BaseModel):
    sender: str = Field(..., min_length=1)
    recipient: str = Field(..., min_length=1)
    content: str = Field(..., min_length=1)
    kind: str = "note"


def _read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise HTTPException(status_code=500, detail=f"Dosya bulunamadi: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"JSON okunamadi: {path.name}") from exc


def _read_ndjson(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    out: list[dict[str, Any]] = []
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
            if isinstance(row, dict):
                out.append(row)
        except Exception:
            continue
    return out


def _sort_by_ts_desc(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    def key(row: dict[str, Any]) -> datetime:
        raw = str(row.get("ts", "")).strip()
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        try:
            return datetime.fromisoformat(raw)
        except Exception:
            return datetime.min

    return sorted(rows, key=key, reverse=True)


def _active_sprint_bundle() -> tuple[str, dict[str, Any], list[dict[str, Any]]]:
    backlog = _read_json(BACKLOG_PATH)

    if "sprints" not in backlog:
        sprint_id = str(backlog.get("sprint", "legacy"))
        sprint_data = {
            "label": backlog.get("label", sprint_id),
            "rules": backlog.get("rules", {}),
        }
        tasks = backlog.get("tasks", [])
        if not isinstance(tasks, list):
            tasks = []
        return sprint_id, sprint_data, tasks

    sprints = backlog.get("sprints", {})
    if not isinstance(sprints, dict) or not sprints:
        raise HTTPException(status_code=500, detail="backlog.json icinde sprint yok")

    sprint_id = str(backlog.get("activeSprint") or list(sprints.keys())[0])
    sprint_data = sprints.get(sprint_id)
    if not isinstance(sprint_data, dict):
        raise HTTPException(status_code=500, detail=f"Aktif sprint bulunamadi: {sprint_id}")

    tasks = sprint_data.get("tasks", [])
    if not isinstance(tasks, list):
        tasks = []

    return sprint_id, sprint_data, tasks


@app.get("/")
def index() -> HTMLResponse:
    return HTMLResponse(INDEX_HTML)


@app.get("/api/sprint")
def get_sprint() -> dict[str, Any]:
    sprint_id, sprint_data, tasks = _active_sprint_bundle()
    return {
        "activeSprint": sprint_id,
        "label": sprint_data.get("label", sprint_id),
        "rules": sprint_data.get("rules", {}),
        "tasks": tasks,
    }


@app.get("/api/agents")
def get_agents() -> dict[str, Any]:
    agents_data = _read_json(AGENTS_PATH)
    agents = agents_data.get("agents", [])
    if not isinstance(agents, list):
        agents = []

    _, _, tasks = _active_sprint_bundle()
    tasks_by_owner: dict[str, list[dict[str, Any]]] = {}
    for task in tasks:
        owner = str(task.get("owner", "")).strip()
        if not owner:
            continue
        tasks_by_owner.setdefault(owner, []).append(task)

    messages = _read_ndjson(MESSAGES_PATH)
    handoffs = _read_ndjson(HANDOFFS_PATH)

    last_message_by_agent: dict[str, str] = {}
    for row in _sort_by_ts_desc(messages):
        sender = str(row.get("from", "")).strip()
        recipient = str(row.get("to", "")).strip()
        ts = str(row.get("ts", "")).strip()
        if sender and sender not in last_message_by_agent:
            last_message_by_agent[sender] = ts
        if recipient and recipient not in last_message_by_agent:
            last_message_by_agent[recipient] = ts

    last_handoff_by_agent: dict[str, str] = {}
    for row in _sort_by_ts_desc(handoffs):
        owner = str(row.get("owner", "")).strip()
        agent = str(row.get("agent", "")).strip()
        ts = str(row.get("ts", "")).strip()
        if owner and owner not in last_handoff_by_agent:
            last_handoff_by_agent[owner] = ts
        if agent and agent not in last_handoff_by_agent:
            last_handoff_by_agent[agent] = ts

    view: list[dict[str, Any]] = []
    for agent in agents:
        agent_id = str(agent.get("id", "")).strip()
        owned_tasks = tasks_by_owner.get(agent_id, [])
        statuses = {str(t.get("status", "")).strip() for t in owned_tasks}

        if "in_progress" in statuses:
            status = "in_progress"
        elif "todo" in statuses:
            status = "queued"
        elif "done" in statuses:
            status = "done"
        else:
            status = "idle"

        view.append(
            {
                "id": agent_id,
                "role": agent.get("role", "developer"),
                "description": agent.get("description", ""),
                "focus": agent.get("focus", []),
                "status": status,
                "tasks": owned_tasks,
                "lastMessageTs": last_message_by_agent.get(agent_id, ""),
                "lastHandoffTs": last_handoff_by_agent.get(agent_id, ""),
            }
        )

    return {"agents": view}


@app.get("/api/messages")
def get_messages(limit: int = 200) -> dict[str, Any]:
    rows = _sort_by_ts_desc(_read_ndjson(MESSAGES_PATH))
    clean_limit = max(1, min(limit, 1000))
    return {"messages": rows[:clean_limit]}


@app.get("/api/handoffs")
def get_handoffs(limit: int = 200) -> dict[str, Any]:
    rows = _sort_by_ts_desc(_read_ndjson(HANDOFFS_PATH))
    clean_limit = max(1, min(limit, 1000))
    return {"handoffs": rows[:clean_limit]}


@app.post("/api/dispatch")
def post_dispatch(payload: DispatchRequest) -> dict[str, Any]:
    if not DISPATCH_PATH.exists():
        raise HTTPException(status_code=500, detail="agents/dispatch.js bulunamadi")

    cmd = ["node", str(DISPATCH_PATH)]
    if payload.all:
        cmd.append("--all")
    if payload.role:
        cmd.extend(["--role", payload.role])
    if payload.sprint:
        cmd.extend(["--sprint", payload.sprint])
    if payload.dry_run:
        cmd.append("--dry-run")

    result = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
    if result.returncode != 0:
        raise HTTPException(
            status_code=500,
            detail={
                "message": "dispatch.js calisamadi",
                "returncode": result.returncode,
                "stderr": result.stderr.strip(),
                "stdout": result.stdout.strip(),
            },
        )

    return {
        "ok": True,
        "command": cmd,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }


@app.post("/api/messages")
def post_message(payload: MessageRequest) -> dict[str, Any]:
    try:
        message_id = send_message(
            sender=payload.sender.strip(),
            recipient=payload.recipient.strip(),
            content=payload.content.strip(),
            kind=payload.kind.strip() or "note",
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {"ok": True, "id": message_id}


INDEX_HTML = """<!doctype html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Dervis Dashboard</title>
  <style>
    :root {
      --bg-a: #eef6ff;
      --bg-b: #f6fff1;
      --ink: #173041;
      --muted: #62707f;
      --line: #d2dde7;
      --card: #ffffff;
      --accent: #0b7a57;
      --todo: #fef5d8;
      --doing: #d9eefc;
      --done: #dcf7e8;
      --shadow: 0 18px 38px rgba(23, 48, 65, 0.14);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      color: var(--ink);
      font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background:
        radial-gradient(900px 500px at -10% -20%, #cbe7ff 0%, transparent 55%),
        radial-gradient(900px 500px at 110% -30%, #d7f5cf 0%, transparent 55%),
        linear-gradient(140deg, var(--bg-a), var(--bg-b));
    }
    .shell {
      max-width: 1280px;
      margin: 0 auto;
      padding: 20px;
      display: grid;
      gap: 16px;
    }
    .panel {
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 14px;
      box-shadow: var(--shadow);
    }
    .head {
      padding: 16px 18px;
      border-bottom: 1px solid var(--line);
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }
    .title {
      font-size: 18px;
      font-weight: 700;
      letter-spacing: 0.2px;
    }
    .meta {
      color: var(--muted);
      font-size: 13px;
    }
    .btn {
      border: 0;
      padding: 9px 12px;
      border-radius: 10px;
      background: var(--accent);
      color: #fff;
      font-weight: 600;
      cursor: pointer;
    }
    .btn.secondary {
      background: #365870;
    }
    .toolbar {
      display: flex;
      gap: 8px;
      align-items: center;
      flex-wrap: wrap;
      width: 100%;
    }
    .toolbar.group {
      justify-content: space-between;
      gap: 12px;
    }
    .toolbar .cluster {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      align-items: center;
    }
    .toolbar input,
    .toolbar select {
      min-width: 120px;
      max-width: 260px;
    }
    .check {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 13px;
      color: var(--muted);
    }
    .stats {
      padding: 12px 14px 14px;
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
      gap: 10px;
    }
    .stat {
      border: 1px solid var(--line);
      border-radius: 10px;
      background: #fff;
      padding: 9px 10px;
    }
    .stat .k {
      font-size: 11px;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.4px;
    }
    .stat .v {
      font-size: 22px;
      font-weight: 700;
      margin-top: 4px;
      color: var(--ink);
    }
    .toast {
      position: fixed;
      right: 18px;
      bottom: 18px;
      background: #133a52;
      color: #fff;
      border-radius: 10px;
      padding: 10px 12px;
      box-shadow: var(--shadow);
      font-size: 13px;
      opacity: 0;
      pointer-events: none;
      transform: translateY(8px);
      transition: opacity 180ms ease, transform 180ms ease;
      z-index: 20;
    }
    .toast.show {
      opacity: 1;
      transform: translateY(0);
    }
    .grid-2 {
      display: grid;
      grid-template-columns: 1.25fr 1fr;
      gap: 16px;
    }
    .kanban {
      padding: 14px;
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
    }
    .col {
      border: 1px solid var(--line);
      border-radius: 12px;
      min-height: 180px;
      padding: 10px;
    }
    .col h4 { margin: 4px 2px 10px; }
    .col.todo { background: var(--todo); }
    .col.in_progress { background: var(--doing); }
    .col.done { background: var(--done); }
    .task {
      background: #fff;
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 8px;
      margin-bottom: 8px;
      font-size: 13px;
      line-height: 1.35;
    }
    .task .owner { color: var(--muted); margin-top: 6px; font-size: 12px; }
    .agents {
      padding: 14px;
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
      gap: 10px;
    }
    .agent {
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 10px;
      background: #fff;
    }
    .status {
      display: inline-block;
      padding: 2px 7px;
      border-radius: 999px;
      font-size: 11px;
      border: 1px solid var(--line);
      margin-top: 6px;
    }
    .status.in_progress { background: #d9eefc; }
    .status.queued { background: #fef5d8; }
    .status.done { background: #dcf7e8; }
    .status.idle { background: #eef2f5; }
    .messages, .handoffs {
      padding: 14px;
      max-height: 310px;
      overflow: auto;
    }
    .msg {
      border-bottom: 1px dashed var(--line);
      padding: 8px 0;
      font-size: 13px;
    }
    .msg b { color: #124e68; }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 12px;
    }
    th, td {
      text-align: left;
      border-bottom: 1px solid var(--line);
      padding: 7px 6px;
      vertical-align: top;
    }
    .composer {
      display: grid;
      grid-template-columns: 160px 160px 1fr 120px;
      gap: 8px;
      padding: 12px 14px 14px;
      border-top: 1px solid var(--line);
    }
    input, select {
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 9px 10px;
      min-width: 0;
    }
    @media (max-width: 980px) {
      .grid-2 { grid-template-columns: 1fr; }
      .kanban { grid-template-columns: 1fr; }
      .composer { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="panel">
      <div class="head">
        <div>
          <div class="title">Dervis Ajan Yonetim Dashboard</div>
          <div class="meta" id="sprintMeta">Yukleniyor...</div>
        </div>
        <button class="btn" id="dispatchBtn">Dispatch Calistir</button>
        <div class="toolbar">
          <span class="meta">Gorev filtre:</span>
          <input id="taskSearch" placeholder="id / baslik / owner" />
          <select id="taskStatusFilter">
            <option value="all">tum durumlar</option>
            <option value="todo">todo</option>
            <option value="in_progress">in_progress</option>
            <option value="done">done</option>
          </select>
          <button class="btn" id="resetFiltersBtn" type="button">Filtreleri Sifirla</button>
        </div>
        <div class="toolbar group">
          <div class="cluster">
            <button class="btn secondary" id="refreshNowBtn" type="button">Simdi Yenile</button>
            <label class="check"><input id="autoRefreshToggle" type="checkbox" checked /> auto yenile</label>
            <select id="refreshInterval">
              <option value="5000">5 sn</option>
              <option value="10000">10 sn</option>
              <option value="30000">30 sn</option>
              <option value="60000">60 sn</option>
            </select>
            <span class="meta" id="lastUpdated">son yenileme: -</span>
          </div>
          <div class="cluster">
            <label class="check"><input id="dispatchDryRun" type="checkbox" /> dry-run</label>
            <label class="check"><input id="dispatchAll" type="checkbox" /> todo dahil</label>
            <select id="dispatchRoleSelect">
              <option value="">dispatch role: tumu</option>
            </select>
          </div>
        </div>
      </div>
      <div class="kanban" id="kanban">
        <div class="col todo"><h4>todo</h4><div id="todoCol"></div></div>
        <div class="col in_progress"><h4>in_progress</h4><div id="progressCol"></div></div>
        <div class="col done"><h4>done</h4><div id="doneCol"></div></div>
      </div>
      <div class="stats" id="statsGrid">
        <article class="stat"><div class="k">Toplam Gorev</div><div class="v" id="statTasksTotal">0</div></article>
        <article class="stat"><div class="k">In Progress</div><div class="v" id="statTasksProgress">0</div></article>
        <article class="stat"><div class="k">Todo</div><div class="v" id="statTasksTodo">0</div></article>
        <article class="stat"><div class="k">Done</div><div class="v" id="statTasksDone">0</div></article>
        <article class="stat"><div class="k">Aktif Ajan</div><div class="v" id="statActiveAgents">0</div></article>
        <article class="stat"><div class="k">Bekleyen Mesaj</div><div class="v" id="statPendingMessages">0</div></article>
      </div>
    </section>

    <section class="panel">
      <div class="head">
        <div class="title">Ajan Durumlari</div>
        <div class="toolbar">
          <input id="agentSearch" placeholder="agent id / rol" />
          <select id="agentStatusFilter">
            <option value="all">tum durumlar</option>
            <option value="in_progress">in_progress</option>
            <option value="queued">queued</option>
            <option value="done">done</option>
            <option value="idle">idle</option>
          </select>
          <select id="agentSort">
            <option value="id">sirala: id</option>
            <option value="status">sirala: durum</option>
            <option value="message">sirala: son mesaj</option>
          </select>
        </div>
      </div>
      <div class="agents" id="agentsGrid"></div>
    </section>

    <section class="grid-2">
      <section class="panel">
        <div class="head">
          <div class="title">Mesaj Kutusu</div>
          <div class="toolbar">
            <input id="messageSearch" placeholder="from / to / icerik" />
            <select id="messageEventFilter">
              <option value="all">tum eventler</option>
              <option value="message">message</option>
              <option value="ack">ack</option>
            </select>
          </div>
        </div>
        <div class="messages" id="messagesBox"></div>
        <form class="composer" id="msgForm">
          <input id="sender" placeholder="from (ornek: panel)" value="panel" />
          <input id="recipient" placeholder="to (ornek: orchestrator)" value="orchestrator" />
          <input id="content" placeholder="Mesaj" />
          <button class="btn" type="submit">Gonder</button>
        </form>
      </section>

      <section class="panel">
        <div class="head">
          <div class="title">Handoff Gecmisi</div>
          <div class="toolbar">
            <input id="handoffSearch" placeholder="agent / task / note" />
          </div>
        </div>
        <div class="handoffs">
          <table>
            <thead>
              <tr><th>ts</th><th>agent</th><th>event</th><th>task</th><th>note</th></tr>
            </thead>
            <tbody id="handoffRows"></tbody>
          </table>
        </div>
      </section>
    </section>
  </main>
  <div id="toast" class="toast"></div>

  <script>
    const sprintMeta = document.getElementById('sprintMeta');
    const todoCol = document.getElementById('todoCol');
    const progressCol = document.getElementById('progressCol');
    const doneCol = document.getElementById('doneCol');
    const agentsGrid = document.getElementById('agentsGrid');
    const messagesBox = document.getElementById('messagesBox');
    const handoffRows = document.getElementById('handoffRows');
    const msgForm = document.getElementById('msgForm');
    const taskSearch = document.getElementById('taskSearch');
    const taskStatusFilter = document.getElementById('taskStatusFilter');
    const agentSearch = document.getElementById('agentSearch');
    const agentStatusFilter = document.getElementById('agentStatusFilter');
    const agentSort = document.getElementById('agentSort');
    const messageSearch = document.getElementById('messageSearch');
    const messageEventFilter = document.getElementById('messageEventFilter');
    const handoffSearch = document.getElementById('handoffSearch');
    const resetFiltersBtn = document.getElementById('resetFiltersBtn');
    const refreshNowBtn = document.getElementById('refreshNowBtn');
    const autoRefreshToggle = document.getElementById('autoRefreshToggle');
    const refreshInterval = document.getElementById('refreshInterval');
    const lastUpdated = document.getElementById('lastUpdated');
    const dispatchDryRun = document.getElementById('dispatchDryRun');
    const dispatchAll = document.getElementById('dispatchAll');
    const dispatchRoleSelect = document.getElementById('dispatchRoleSelect');
    const statTasksTotal = document.getElementById('statTasksTotal');
    const statTasksProgress = document.getElementById('statTasksProgress');
    const statTasksTodo = document.getElementById('statTasksTodo');
    const statTasksDone = document.getElementById('statTasksDone');
    const statActiveAgents = document.getElementById('statActiveAgents');
    const statPendingMessages = document.getElementById('statPendingMessages');
    const toast = document.getElementById('toast');
    const PERSIST_KEY = 'dervis.dashboard.filters.v1';
    const persistedControls = {
      taskSearch,
      taskStatusFilter,
      agentSearch,
      agentStatusFilter,
      agentSort,
      messageSearch,
      messageEventFilter,
      handoffSearch,
    };

    let latestSprint = null;
    let latestAgents = [];
    let latestMessages = [];
    let latestHandoffs = [];
    let refreshTimer = null;
    let toastTimer = null;

    function esc(value) {
      return String(value || '').replace(/[&<>"']/g, (m) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
    }

    function n(value) {
      return String(value || '').toLowerCase();
    }

    function statusRank(status) {
      if (status === 'in_progress') return 0;
      if (status === 'queued') return 1;
      if (status === 'todo') return 2;
      if (status === 'done') return 3;
      return 4;
    }

    function parseTs(value) {
      const d = new Date(String(value || ''));
      return Number.isNaN(d.getTime()) ? null : d;
    }

    function showToast(text) {
      toast.textContent = text;
      toast.classList.add('show');
      if (toastTimer) clearTimeout(toastTimer);
      toastTimer = setTimeout(() => {
        toast.classList.remove('show');
      }, 1800);
    }

    function scheduleRefreshLoop() {
      if (refreshTimer) {
        clearInterval(refreshTimer);
        refreshTimer = null;
      }
      if (!autoRefreshToggle.checked) return;
      const ms = Math.max(2000, Number(refreshInterval.value || 5000));
      refreshTimer = setInterval(refresh, ms);
    }

    function updateStats() {
      const tasks = (latestSprint && latestSprint.tasks) ? latestSprint.tasks : [];
      const total = tasks.length;
      let todo = 0;
      let progress = 0;
      let done = 0;
      for (const t of tasks) {
        if (t.status === 'done') done += 1;
        else if (t.status === 'in_progress') progress += 1;
        else todo += 1;
      }

      let activeAgents = 0;
      for (const a of latestAgents) {
        if (a.status === 'in_progress' || a.status === 'queued') activeAgents += 1;
      }

      const acked = new Set();
      for (const m of latestMessages) {
        if (m.event === 'ack' && m.message_id) acked.add(m.message_id);
      }
      let pending = 0;
      for (const m of latestMessages) {
        if (m.event === 'message' && m.id && !acked.has(m.id)) pending += 1;
      }

      statTasksTotal.textContent = String(total);
      statTasksProgress.textContent = String(progress);
      statTasksTodo.textContent = String(todo);
      statTasksDone.textContent = String(done);
      statActiveAgents.textContent = String(activeAgents);
      statPendingMessages.textContent = String(pending);
    }

    function syncDispatchRoleOptions() {
      const selected = dispatchRoleSelect.value;
      const unique = Array.from(new Set(latestAgents.map((a) => String(a.id || '').trim()).filter(Boolean))).sort();
      dispatchRoleSelect.innerHTML = '<option value="">dispatch role: tumu</option>';
      for (const role of unique) {
        dispatchRoleSelect.insertAdjacentHTML('beforeend', `<option value="${esc(role)}">${esc(role)}</option>`);
      }
      if (selected && unique.includes(selected)) {
        dispatchRoleSelect.value = selected;
      }
    }

    function saveFilterState() {
      const payload = {};
      for (const [key, control] of Object.entries(persistedControls)) {
        payload[key] = control.value || '';
      }
      localStorage.setItem(PERSIST_KEY, JSON.stringify(payload));
    }

    function resetFilterState() {
      taskSearch.value = '';
      taskStatusFilter.value = 'all';
      agentSearch.value = '';
      agentStatusFilter.value = 'all';
      agentSort.value = 'id';
      messageSearch.value = '';
      messageEventFilter.value = 'all';
      handoffSearch.value = '';
      localStorage.removeItem(PERSIST_KEY);
      renderFromCache();
    }

    function restoreFilterState() {
      const raw = localStorage.getItem(PERSIST_KEY);
      if (!raw) return;
      try {
        const data = JSON.parse(raw);
        for (const [key, control] of Object.entries(persistedControls)) {
          const value = data[key];
          if (typeof value !== 'string') continue;
          if (control.tagName === 'SELECT') {
            const match = Array.from(control.options).some((o) => o.value === value);
            if (match) control.value = value;
          } else {
            control.value = value;
          }
        }
      } catch (_) {
        // ignore invalid localStorage payload
      }
    }

    async function jsonFetch(url, options) {
      const res = await fetch(url, options);
      const data = await res.json();
      if (!res.ok) {
        const text = typeof data.detail === 'string' ? data.detail : JSON.stringify(data.detail || data);
        throw new Error(text || 'istek hatasi');
      }
      return data;
    }

    function renderTasks(tasks) {
      todoCol.innerHTML = '';
      progressCol.innerHTML = '';
      doneCol.innerHTML = '';

      const q = n(taskSearch.value).trim();
      const status = taskStatusFilter.value;
      const filtered = tasks.filter((t) => {
        if (status !== 'all' && t.status !== status) return false;
        if (!q) return true;
        return `${n(t.id)} ${n(t.title)} ${n(t.owner)}`.includes(q);
      });

      for (const t of filtered) {
        const card = `<article class="task"><div><b>${esc(t.id)}</b> - ${esc(t.title)}</div><div class="owner">owner: ${esc(t.owner || '-')}</div></article>`;
        if (t.status === 'done') doneCol.insertAdjacentHTML('beforeend', card);
        else if (t.status === 'in_progress') progressCol.insertAdjacentHTML('beforeend', card);
        else todoCol.insertAdjacentHTML('beforeend', card);
      }
    }

    function renderAgents(agents) {
      agentsGrid.innerHTML = '';

      const q = n(agentSearch.value).trim();
      const status = agentStatusFilter.value;
      const sortMode = agentSort.value;
      const filtered = agents.filter((a) => {
        if (status !== 'all' && a.status !== status) return false;
        if (!q) return true;
        return `${n(a.id)} ${n(a.role)} ${n(a.description)}`.includes(q);
      });

      filtered.sort((a, b) => {
        if (sortMode === 'status') {
          return statusRank(a.status) - statusRank(b.status) || n(a.id).localeCompare(n(b.id));
        }
        if (sortMode === 'message') {
          return n(b.lastMessageTs).localeCompare(n(a.lastMessageTs)) || n(a.id).localeCompare(n(b.id));
        }
        return n(a.id).localeCompare(n(b.id));
      });

      for (const a of filtered) {
        agentsGrid.insertAdjacentHTML('beforeend', `
          <article class="agent">
            <div><b>${esc(a.id)}</b></div>
            <div>${esc(a.role || '-')}</div>
            <div class="status ${esc(a.status)}">${esc(a.status)}</div>
            <div class="meta" style="margin-top:6px;">task: ${a.tasks ? a.tasks.length : 0}</div>
            <div class="meta">last msg: ${esc(a.lastMessageTs || '-')}</div>
          </article>
        `);
      }
    }

    function renderMessages(messages) {
      messagesBox.innerHTML = '';

      const q = n(messageSearch.value).trim();
      const eventFilter = messageEventFilter.value;
      const filtered = messages.filter((m) => {
        const eventName = m.event || '';
        if (eventFilter !== 'all' && eventName !== eventFilter) return false;
        if (!q) return true;
        return `${n(m.from || m.agent)} ${n(m.to || m.message_id)} ${n(m.content || m.note)} ${n(eventName)}`.includes(q);
      });

      for (const m of filtered.slice(0, 80)) {
        const from = m.from || m.agent || '-';
        const to = m.to || m.message_id || '-';
        const label = m.event || m.kind || 'event';
        const content = m.content || m.note || '-';
        messagesBox.insertAdjacentHTML('beforeend', `
          <div class="msg">
            <div><b>${esc(from)}</b> -> <b>${esc(to)}</b> <span class="meta">(${esc(label)})</span></div>
            <div>${esc(content)}</div>
            <div class="meta">${esc(m.ts || '')}</div>
          </div>
        `);
      }
    }

    function renderHandoffs(handoffs) {
      handoffRows.innerHTML = '';

      const q = n(handoffSearch.value).trim();
      const filtered = handoffs.filter((h) => {
        if (!q) return true;
        return `${n(h.ts)} ${n(h.agent || h.owner)} ${n(h.event)} ${n(h.task)} ${n(h.note || h.message)}`.includes(q);
      });

      for (const h of filtered.slice(0, 120)) {
        handoffRows.insertAdjacentHTML('beforeend', `
          <tr>
            <td>${esc(h.ts || '')}</td>
            <td>${esc(h.agent || h.owner || '')}</td>
            <td>${esc(h.event || '')}</td>
            <td>${esc(h.task || '')}</td>
            <td>${esc(h.note || '')}</td>
          </tr>
        `);
      }
    }

    function renderFromCache() {
      if (!latestSprint) return;
      renderTasks(latestSprint.tasks || []);
      renderAgents(latestAgents);
      renderMessages(latestMessages);
      renderHandoffs(latestHandoffs);
      updateStats();
    }

    async function refresh() {
      try {
        const [sprint, agents, messages, handoffs] = await Promise.all([
          jsonFetch('/api/sprint'),
          jsonFetch('/api/agents'),
          jsonFetch('/api/messages?limit=200'),
          jsonFetch('/api/handoffs?limit=200'),
        ]);
        latestSprint = sprint;
        latestAgents = agents.agents || [];
        latestMessages = messages.messages || [];
        latestHandoffs = handoffs.handoffs || [];
        syncDispatchRoleOptions();
        sprintMeta.textContent = `${sprint.activeSprint} - ${sprint.label}`;
        lastUpdated.textContent = `son yenileme: ${new Date().toLocaleTimeString('tr-TR')}`;
        renderFromCache();
      } catch (err) {
        sprintMeta.textContent = `Hata: ${err.message}`;
        showToast('Yenileme hatasi');
      }
    }

    document.getElementById('dispatchBtn').addEventListener('click', async () => {
      try {
        const payload = {
          sprint: null,
          all: dispatchAll.checked,
          dry_run: dispatchDryRun.checked,
        };
        if (dispatchRoleSelect.value) {
          payload.role = dispatchRoleSelect.value;
        }
        await jsonFetch('/api/dispatch', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        showToast('Dispatch tamamlandi');
        await refresh();
      } catch (err) {
        showToast('Dispatch hatasi');
        alert('Dispatch hatasi: ' + err.message);
      }
    });

    msgForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const sender = document.getElementById('sender').value.trim();
      const recipient = document.getElementById('recipient').value.trim();
      const content = document.getElementById('content').value.trim();
      if (!sender || !recipient || !content) return;
      try {
        await jsonFetch('/api/messages', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ sender, recipient, content, kind: 'note' }),
        });
        document.getElementById('content').value = '';
        showToast('Mesaj gonderildi');
        await refresh();
      } catch (err) {
        showToast('Mesaj gonderilemedi');
        alert('Mesaj gonderilemedi: ' + err.message);
      }
    });

    refreshNowBtn.addEventListener('click', async () => {
      await refresh();
      showToast('Veriler guncellendi');
    });

    autoRefreshToggle.addEventListener('change', scheduleRefreshLoop);
    refreshInterval.addEventListener('change', scheduleRefreshLoop);

    [
      taskSearch,
      taskStatusFilter,
      agentSearch,
      agentStatusFilter,
      agentSort,
      messageSearch,
      messageEventFilter,
      handoffSearch,
    ].forEach((el) => {
      el.addEventListener('input', () => {
        saveFilterState();
        renderFromCache();
      });
      el.addEventListener('change', () => {
        saveFilterState();
        renderFromCache();
      });
    });

    resetFiltersBtn.addEventListener('click', resetFilterState);

    restoreFilterState();
    refresh();
    scheduleRefreshLoop();
  </script>
</body>
</html>
"""


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8766, reload=False)
