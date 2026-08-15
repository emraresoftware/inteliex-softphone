from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from llm_bridge import chat as llm_chat
from llm_bridge import get_default_model_name


MODEL_NAME = get_default_model_name()
MODEL_OPTIONS = {
    "num_ctx": 16384,
    "temperature": 0.2,
    "top_p": 0.9,
}


@dataclass
class ProjectSpec:
    project_name: str
    project_slug: str
    summary: str
    template: str
    primary_goal: str
    features: list[str]
    endpoints: list[dict[str, str]]
    desktop_root: str


def _slugify(value: str) -> str:
    normalized = value.strip().lower()
    replacements = str.maketrans({
        "c": "c",
        "g": "g",
        "i": "i",
        "o": "o",
        "s": "s",
        "u": "u",
        "C": "c",
        "G": "g",
        "I": "i",
        "O": "o",
        "S": "s",
        "U": "u",
        "ç": "c",
        "ğ": "g",
        "ı": "i",
        "ö": "o",
        "ş": "s",
        "ü": "u",
    })
    normalized = normalized.translate(replacements)
    normalized = re.sub(r"[^a-z0-9]+", "-", normalized)
    normalized = normalized.strip("-")
    return normalized or f"emare-proje-{int(time.time())}"


def _extract_json_dict(text: str) -> dict[str, Any] | None:
    decoder = json.JSONDecoder()
    for index, char in enumerate(text):
        if char != "{":
            continue
        try:
            parsed, _ = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            return parsed
    return None


def _conversation_excerpt(messages: list[dict[str, str]], limit: int = 24) -> str:
    lines: list[str] = []
    for item in messages[-limit:]:
        role = str(item.get("role", "user")).strip() or "user"
        content = str(item.get("content", "")).strip()
        if not content:
            continue
        lines.append(f"{role}: {content}")
    return "\n".join(lines)


def infer_project_spec(messages: list[dict[str, str]], desktop_root: str | None = None) -> ProjectSpec:
    excerpt = _conversation_excerpt(messages)
    desktop = desktop_root or str(Path.home() / "Desktop")
    system_prompt = (
        "Sen Emare Asistan adli yerel urun mimarisin. "
        "Kullanici sohbetinden bir yazilim projesi brifi cikaracaksin. "
        "Sadece JSON don. Template secenekleri: node-express-api, python-fastapi-api, next-web-app. "
        "Belirsizlik varsa node-express-api sec. "
        "JSON semasi: "
        "{project_name, project_slug, summary, template, primary_goal, features, endpoints}."
    )
    user_prompt = (
        "Asagidaki sohbetten uygulanabilir bir proje brifi cikar. "
        "project_slug kisa ve klasor-uyumlu olsun. "
        "features 4-6 madde olsun. endpoints yalnizca obje listesi olsun: {method, path, purpose}.\n\n"
        f"SOHBET:\n{excerpt}"
    )

    raw_content = ""
    try:
        response = llm_chat(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            options=MODEL_OPTIONS,
            timeout=90,
        )
        raw_content = str(response.get("message", {}).get("content", "")).strip()
    except Exception:
        raw_content = ""

    parsed = _extract_json_dict(raw_content) or {}
    project_name = str(parsed.get("project_name", "Emare Otonom Proje")).strip() or "Emare Otonom Proje"
    project_slug = _slugify(str(parsed.get("project_slug", "")).strip() or project_name)
    summary = str(parsed.get("summary", "Sohbetten uretildi.")).strip() or "Sohbetten uretildi."
    template = str(parsed.get("template", "node-express-api")).strip() or "node-express-api"
    if template not in {"node-express-api", "python-fastapi-api", "next-web-app"}:
        template = "node-express-api"
    primary_goal = str(parsed.get("primary_goal", summary)).strip() or summary

    features = parsed.get("features")
    if not isinstance(features, list):
        features = []
    normalized_features = [str(item).strip() for item in features if str(item).strip()]
    if not normalized_features:
        normalized_features = [
            "Saglik kontrol endpointi",
            "Ana is akisi endpointi",
            "Temel veri saklama katmani",
            "Auth ve rate-limit",
        ]

    endpoints = parsed.get("endpoints")
    normalized_endpoints: list[dict[str, str]] = []
    if isinstance(endpoints, list):
        for item in endpoints:
            if not isinstance(item, dict):
                continue
            method = str(item.get("method", "GET")).strip().upper() or "GET"
            path = str(item.get("path", "/health")).strip() or "/health"
            purpose = str(item.get("purpose", "Endpoint")).strip() or "Endpoint"
            normalized_endpoints.append({"method": method, "path": path, "purpose": purpose})
    if not normalized_endpoints:
        normalized_endpoints = [
            {"method": "GET", "path": "/health", "purpose": "Saglik kontrolu"},
            {"method": "POST", "path": "/api/v1/chat", "purpose": "Temel sohbet veya is akisi endpointi"},
        ]

    return ProjectSpec(
        project_name=project_name,
        project_slug=project_slug,
        summary=summary,
        template=template,
        primary_goal=primary_goal,
        features=normalized_features,
        endpoints=normalized_endpoints,
        desktop_root=desktop,
    )


def _ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def _write_text(path: Path, content: str) -> None:
    _ensure_dir(path.parent)
    path.write_text(content, encoding="utf-8")


def _json_dump(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def _build_agent_specs(spec: ProjectSpec) -> list[dict[str, Any]]:
    return [
        {
            "id": "yonetici",
            "folder": "yonetici",
            "role": "manager",
            "focus": ["planlama", "gorev dagitimi", "bagimlilik", "kalite kapisi", "final onay"],
            "prompt": "TALIMATLAR.md dosyasindaki isaretsiz maddeleri uygula. Kodlari sadece proje klasorune yaz. Diger ajanlari koordine et."
        },
        {
            "id": "agent1",
            "folder": "agent1",
            "role": "developer",
            "focus": ["sunucu", "uygulama iskeleti", "middleware", "logging", "config"],
            "prompt": "TALIMATLAR.md dosyasindaki isaretsiz maddeleri uygula. Kodlari sadece proje klasorune yaz. Express veya ana uygulama iskeletine odaklan."
        },
        {
            "id": "agent2",
            "folder": "agent2",
            "role": "developer",
            "focus": ["api", "route", "controller", "endpoint", "dokumantasyon"],
            "prompt": "TALIMATLAR.md dosyasindaki isaretsiz maddeleri uygula. Kodlari sadece proje klasorune yaz. Route ve controller katmanina odaklan."
        },
        {
            "id": "agent3",
            "folder": "agent3",
            "role": "developer",
            "focus": ["service", "storage", "model", "veri akisi"],
            "prompt": "TALIMATLAR.md dosyasindaki isaretsiz maddeleri uygula. Kodlari sadece proje klasorune yaz. Service ve storage katmanina odaklan."
        },
        {
            "id": "agent4",
            "folder": "agent4",
            "role": "developer",
            "focus": ["security", "validation", "auth", "rate limit"],
            "prompt": "TALIMATLAR.md dosyasindaki isaretsiz maddeleri uygula. Kodlari sadece proje klasorune yaz. Guvenlik, auth ve validation katmanina odaklan."
        },
        {
            "id": "agent5",
            "folder": "agent5",
            "role": "developer",
            "focus": ["test", "smoke", "coverage", "quality gate"],
            "prompt": "TALIMATLAR.md dosyasindaki isaretsiz maddeleri uygula. Kodlari sadece proje klasorune yaz. Testler ve kalite kapisina odaklan."
        },
    ]


def _project_dirs_for_template(template: str) -> list[str]:
    if template == "python-fastapi-api":
        return [
            "proje/app/routes",
            "proje/app/services",
            "proje/app/models",
            "proje/app/core",
            "proje/tests",
            "proje/docs",
            "proje/data",
        ]
    if template == "next-web-app":
        return [
            "proje/app",
            "proje/components",
            "proje/lib",
            "proje/public",
            "proje/tests",
            "proje/docs",
        ]
    return [
        "proje/src/routes",
        "proje/src/controllers",
        "proje/src/services",
        "proje/src/middleware",
        "proje/src/storage",
        "proje/src/data",
        "proje/tests",
        "proje/docs",
    ]


def _base_project_files(spec: ProjectSpec) -> dict[str, str]:
    endpoints_lines = "\n".join(
        f"- `{item['method']} {item['path']}` - {item['purpose']}" for item in spec.endpoints
    )
    feature_lines = "\n".join(f"- {item}" for item in spec.features)

    if spec.template == "python-fastapi-api":
        package_text = _json_dump({
            "project": spec.project_slug,
            "template": spec.template,
            "run": "uvicorn app.main:app --reload --port 8000",
        })
        extra = {
            "proje/requirements.txt": "fastapi\nuvicorn[standard]\npydantic\npytest\nhttpx\n",
            "proje/app/main.py": "from fastapi import FastAPI\n\napp = FastAPI(title=\"%s\")\n\n\n@app.get('/health')\ndef health():\n    return {'status': 'ok'}\n" % spec.project_name,
            "proje/data/messages.json": "[]\n",
            "proje/docs/API.md": "# API\n\n%s\n" % endpoints_lines,
        }
    elif spec.template == "next-web-app":
        package_text = _json_dump({
            "name": spec.project_slug,
            "private": True,
            "scripts": {
                "dev": "next dev",
                "build": "next build",
                "start": "next start",
                "lint": "next lint"
            }
        })
        extra = {
            "proje/package.json": package_text,
            "proje/app/page.tsx": "export default function Home() {\n  return <main>%s</main>;\n}\n" % spec.project_name,
            "proje/docs/API.md": "# Uygulama Akislari\n\n%s\n" % feature_lines,
        }
        package_text = ""
    else:
        package_text = _json_dump({
            "name": spec.project_slug,
            "version": "0.1.0",
            "private": True,
            "scripts": {
                "dev": "nodemon src/index.js",
                "start": "node src/index.js",
                "test": "jest --runInBand"
            },
            "dependencies": {
                "cors": "^2.8.5",
                "express": "^4.21.2",
                "express-rate-limit": "^7.4.1",
                "helmet": "^8.0.0",
                "joi": "^17.13.3",
                "uuid": "^11.0.5"
            },
            "devDependencies": {
                "jest": "^29.7.0",
                "nodemon": "^3.1.10",
                "supertest": "^7.1.1"
            }
        })
        extra = {
            "proje/package.json": package_text,
            "proje/src/index.js": "const app = require('./app');\nconst port = process.env.PORT || 3000;\napp.listen(port, () => console.log(`server ${port}`));\n",
            "proje/src/app.js": "const express = require('express');\nconst app = express();\napp.get('/health', (_req, res) => res.json({ status: 'ok' }));\nmodule.exports = app;\n",
            "proje/src/data/messages.json": "[]\n",
            "proje/docs/API.md": "# API\n\n%s\n" % endpoints_lines,
            "proje/jest.config.js": "module.exports = { testEnvironment: 'node' };\n",
        }

    base_files = {
        "README.md": (
            f"# {spec.project_name}\n\n"
            f"{spec.summary}\n\n"
            "## Otonom Akis\n\n"
            "- Kullanici Emare Asistan ile proje brifini netlestirir\n"
            "- 'Yazmaya basla' komutu ile workspace otomatik kurulur\n"
            "- Agent klasorleri acilir ve ilk prompt hazirlanir\n"
        ),
        "project_brief.json": _json_dump(asdict(spec)),
        "proje/README.md": (
            f"# {spec.project_name}\n\n"
            f"## Hedef\n{spec.primary_goal}\n\n"
            "## Ozellikler\n"
            f"{feature_lines}\n\n"
            "## Endpointler\n"
            f"{endpoints_lines}\n"
        ),
        "proje/.env.example": "PORT=3000\nNODE_ENV=development\nAPI_KEY=change-me\n",
    }
    base_files.update(extra)
    return base_files


def _task_blueprints(spec: ProjectSpec) -> list[dict[str, Any]]:
    return [
        {
            "id": "S1-000",
            "title": "Proje iskeleti ve sprint koordinasyonu",
            "owner": "yonetici",
            "status": "in_progress",
            "dependsOn": [],
            "checklist": [
                "proje brifi ve hedefleri README icinde net",
                "proje package veya requirements tabani hazir",
                "diger ajanlar icin TALIMATLAR dagitildi",
                "handoffs.ndjson acilis kaydi eklendi",
            ],
        },
        {
            "id": "S1-001",
            "title": "Uygulama iskeleti ve runtime kurulumu",
            "owner": "agent1",
            "status": "in_progress",
            "dependsOn": [],
            "checklist": [
                "ana uygulama giris noktasi hazir",
                "runtime veya middleware iskeleti kuruldu",
                "health endpointi veya temel sayfa hazir",
                "loglama ve config tabani eklendi",
            ],
        },
        {
            "id": "S1-002",
            "title": "Ana API veya etkileim katmani",
            "owner": "agent2",
            "status": "in_progress",
            "dependsOn": [],
            "checklist": [
                "ana route veya ekran akislarinin iskeleti hazir",
                "controller veya action katmani yazildi",
                "istek ve yanit sekli dokumante edildi",
                "hata kodlari tutarli hale getirildi",
            ],
        },
        {
            "id": "S1-003",
            "title": "Service ve veri katmani",
            "owner": "agent3",
            "status": "in_progress",
            "dependsOn": [],
            "checklist": [
                "service katmani yazildi",
                "storage veya veri adapteri eklendi",
                "baslangic veri dosyasi hazir",
                "okuma yazma akislarinin temel testi dusunuldu",
            ],
        },
        {
            "id": "S1-004",
            "title": "Guvenlik validation ve auth",
            "owner": "agent4",
            "status": "in_progress",
            "dependsOn": [],
            "checklist": [
                "validation middleware veya schema hazir",
                "auth mekanizmasi eklendi",
                "rate-limit veya abuse korumasi eklendi",
                "ortam degiskenlerinden gizli bilgiler okunuyor",
            ],
        },
        {
            "id": "S1-005",
            "title": "Testler ve kalite kapisi",
            "owner": "agent5",
            "status": "todo",
            "dependsOn": ["S1-001", "S1-002", "S1-003", "S1-004"],
            "checklist": [
                "unit testler yazildi",
                "integration veya smoke testler yazildi",
                "test komutu yesil",
                "kalite kapisi gecer durumda",
            ],
        },
    ]


def _agents_json(spec: ProjectSpec, agent_specs: list[dict[str, Any]]) -> str:
    payload = {
        "version": 1,
        "projectRoot": "./proje",
        "template": spec.template,
        "agents": [
            {
                "id": item["id"],
                "path": f"./{item['folder']}",
                "role": item["role"],
                "focus": item["focus"],
            }
            for item in agent_specs
        ],
    }
    return _json_dump(payload)


def _backlog_json(spec: ProjectSpec) -> str:
    ownership = {
        "yonetici": ["proje/package.json", "proje/README.md", "README.md", "project_brief.json", "backlog.json"],
        "agent1": ["proje/src/index.js", "proje/src/app.js", "proje/app/main.py", "proje/app/page.tsx", "proje/src/middleware/**"],
        "agent2": ["proje/src/routes/**", "proje/src/controllers/**", "proje/docs/API.md", "proje/app/routes/**"],
        "agent3": ["proje/src/services/**", "proje/src/storage/**", "proje/src/data/**", "proje/app/services/**", "proje/data/**"],
        "agent4": ["proje/src/middleware/auth.js", "proje/src/middleware/validate.js", "proje/src/middleware/rateLimit.js", "proje/app/core/**"],
        "agent5": ["proje/tests/**", "proje/jest.config.js", "proje/pytest.ini"],
    }
    payload = {
        "version": 1,
        "activeSprint": "S1",
        "sprints": {
            "S1": {
                "label": f"{spec.project_name} - ilk sprint",
                "projectPath": "./proje",
                "rules": {
                    "singleOwnerPerTask": True,
                    "maxInProgressPerAgent": 1,
                    "mergeRequires": ["tests", "review", "no-conflict"],
                    "fileOwnership": ownership,
                },
                "tasks": _task_blueprints(spec),
            }
        },
    }
    return _json_dump(payload)


def _dispatch_js() -> str:
    return """#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const BACKLOG_PATH = path.join(ROOT, 'backlog.json');
const AGENTS_PATH = path.join(ROOT, 'agents.json');
const HANDOFFS_PATH = path.join(ROOT, 'handoffs.ndjson');
const args = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const ALL = args.includes('--all');

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function ensureDir(dirPath) {
  if (!DRY_RUN) fs.mkdirSync(dirPath, { recursive: true });
}

function appendHandoff(entry) {
  const line = JSON.stringify(entry) + '\\n';
  if (DRY_RUN) {
    console.log('[dry-run] handoff:', line.trim());
    return;
  }
  fs.appendFileSync(HANDOFFS_PATH, line, 'utf8');
}

function writeFile(filePath, content) {
  if (DRY_RUN) {
    console.log(`[dry-run] write ${filePath}`);
    console.log(content);
    return;
  }
  fs.writeFileSync(filePath, content, 'utf8');
}

function depsResolved(task, tasks) {
  if (!task.dependsOn || task.dependsOn.length === 0) return true;
  const doneIds = new Set(tasks.filter(t => t.status === 'done').map(t => t.id));
  return task.dependsOn.every(id => doneIds.has(id));
}

function renderInstructions(agent, ownership) {
  return [
    '---',
    'applyTo: "**"',
    '---',
    '',
    `# Otonom Workspace - ${agent.id}`,
    '',
    '## Rol',
    `${agent.role} - ${(agent.focus || []).join(', ')}`,
    '',
    '## Kurallar',
    '- Kod yalnizca ../proje klasorune yazilacak.',
    '- Kendi TALIMATLAR.md dosyandaki isaretsiz maddeleri uygula.',
    '- Tamamlanan maddeyi - [x] yap.',
    '- Baska agent klasorlerine yazma.',
    '',
    '## Dosya Sahipligi',
    ...ownership.map(item => `- ${item}`),
    ''
  ].join('\\n');
}

function renderTaskBlock(task) {
  return [
    `## ${task.id} - ${task.title}`,
    `> sprint: ${task.sprint} | durum: ${task.status}`,
    '',
    ...(task.checklist || [task.title]).map(item => `- [ ] ${item}`),
    ''
  ].join('\\n');
}

function renderWaiting(agentId) {
  return [
    `# TALIMATLAR - ${agentId}`,
    '',
    'Su an aktif gorev yok veya bagimliliklar kapanmadi.',
    '',
    '- [ ] Beklemede kal',
    '- [ ] Yonetici yeni gorev actiginda tekrar dispatch calistir',
    ''
  ].join('\\n');
}

function main() {
  const backlog = readJson(BACKLOG_PATH);
  const agentsJson = readJson(AGENTS_PATH);
  const sprintId = backlog.activeSprint;
  const sprint = backlog.sprints[sprintId];
  const tasks = (sprint.tasks || []).map(task => ({ ...task, sprint: sprintId }));
  const ownership = sprint.rules.fileOwnership || {};
  const allowedStatuses = ALL ? ['in_progress', 'todo'] : ['in_progress'];

  console.log(`[sprint] ${sprintId} - ${sprint.label}`);

  for (const agent of agentsJson.agents) {
    const agentDir = path.join(ROOT, agent.path);
    ensureDir(agentDir);

    writeFile(path.join(agentDir, '.instructions.md'), renderInstructions(agent, ownership[agent.id] || []));

    const agentTasks = tasks.filter(task => {
      if (task.owner !== agent.id) return false;
      if (!allowedStatuses.includes(task.status)) return false;
      if (task.status === 'todo' && !depsResolved(task, tasks)) return false;
      return true;
    });

    if (agentTasks.length === 0) {
      writeFile(path.join(agentDir, 'TALIMATLAR.md'), renderWaiting(agent.id));
      continue;
    }

    const content = [`# TALIMATLAR - ${agent.id}`, '']
      .concat(agentTasks.map(renderTaskBlock))
      .join('\\n');
    writeFile(path.join(agentDir, 'TALIMATLAR.md'), content);

    for (const task of agentTasks) {
      appendHandoff({
        ts: new Date().toISOString(),
        event: 'dispatch',
        sprint: sprintId,
        task: task.id,
        owner: task.owner,
      });
      console.log(`[dispatch] ${task.id} -> ${agent.path}/TALIMATLAR.md`);
    }
  }
}

main();
"""


def _workspace_json(root_name: str) -> str:
    return _json_dump(
        {
            "folders": [
                {"path": "..", "name": root_name},
                {"path": "../proje", "name": "Proje"},
            ],
            "settings": {"github.copilot.chat.agent.enabled": True},
            "extensions": {"recommendations": ["github.copilot", "github.copilot-chat"]},
        }
    )


def _copy_to_clipboard(text: str) -> bool:
    try:
        result = subprocess.run(["pbcopy"], input=text, text=True, capture_output=True, timeout=5)
        return result.returncode == 0
    except Exception:
        return False


def _run_osascript(lines: list[str]) -> bool:
    try:
        command = ["osascript"]
        for line in lines:
            command.extend(["-e", line])
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        return result.returncode == 0
    except Exception:
        return False


def _open_workspace(workspace_path: Path) -> bool:
    code_bin = shutil.which("code")
    if code_bin:
        result = subprocess.run([code_bin, str(workspace_path)], capture_output=True, text=True, timeout=15)
        return result.returncode == 0
    result = subprocess.run(["open", "-na", "Visual Studio Code", str(workspace_path)], capture_output=True, text=True, timeout=20)
    return result.returncode == 0


def _paste_prompt_into_vscode() -> bool:
    script = [
        'tell application "Visual Studio Code" to activate',
        'delay 1.2',
        'tell application "System Events"',
        '  keystroke "p" using {command down, shift down}',
        '  delay 0.4',
        '  keystroke "Chat: Open Chat"',
        '  delay 0.2',
        '  key code 36',
        '  delay 1.0',
        '  keystroke "v" using {command down}',
        '  delay 0.2',
        '  key code 36',
        'end tell',
    ]
    return _run_osascript(script)


def _bootstrap_tree(root_dir: Path, spec: ProjectSpec) -> None:
    _ensure_dir(root_dir)
    for relative_dir in _project_dirs_for_template(spec.template):
        _ensure_dir(root_dir / relative_dir)
    for path_str, content in _base_project_files(spec).items():
        _write_text(root_dir / path_str, content)

    agent_specs = _build_agent_specs(spec)
    _write_text(root_dir / "agents.json", _agents_json(spec, agent_specs))
    _write_text(root_dir / "backlog.json", _backlog_json(spec))
    _write_text(root_dir / "dispatch.js", _dispatch_js())
    _write_text(root_dir / "handoffs.ndjson", "")

    for agent in agent_specs:
        agent_dir = root_dir / agent["folder"]
        _ensure_dir(agent_dir)
        _write_text(agent_dir / f"{agent['folder']}.code-workspace", _workspace_json(spec.project_name))
        _write_text(agent_dir / "FIRST_PROMPT.txt", agent["prompt"] + "\n")


def _run_dispatch(root_dir: Path) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["node", "dispatch.js"],
            cwd=str(root_dir),
            capture_output=True,
            text=True,
            timeout=30,
        )
    except Exception as exc:
        return False, str(exc)
    output = (result.stdout or "") + (result.stderr or "")
    return result.returncode == 0, output.strip()


def launch_workspaces(root_dir: Path, spec: ProjectSpec, auto_paste: bool = True) -> dict[str, Any]:
    agent_specs = _build_agent_specs(spec)
    opened: list[str] = []
    pasted: list[str] = []
    failed: list[str] = []

    for agent in agent_specs:
        workspace_path = root_dir / agent["folder"] / f"{agent['folder']}.code-workspace"
        if not _open_workspace(workspace_path):
            failed.append(agent["id"])
            continue
        opened.append(agent["id"])
        _copy_to_clipboard(agent["prompt"])
        time.sleep(1.2)
        if auto_paste and _paste_prompt_into_vscode():
            pasted.append(agent["id"])
        time.sleep(0.8)

    return {"opened": opened, "pasted": pasted, "failed": failed}


def build_autonomous_project(messages: list[dict[str, str]], desktop_root: str | None = None, open_workspaces: bool = True, auto_paste: bool = True) -> dict[str, Any]:
    spec = infer_project_spec(messages, desktop_root=desktop_root)
    root_dir = Path(spec.desktop_root).expanduser() / spec.project_slug
    _bootstrap_tree(root_dir, spec)
    dispatch_ok, dispatch_output = _run_dispatch(root_dir)
    workspace_result = {"opened": [], "pasted": [], "failed": []}
    if open_workspaces:
        workspace_result = launch_workspaces(root_dir, spec, auto_paste=auto_paste)
    return {
        "spec": asdict(spec),
        "root_dir": str(root_dir),
        "dispatch_ok": dispatch_ok,
        "dispatch_output": dispatch_output,
        "workspace_result": workspace_result,
    }


def start_from_chat(messages: list[dict[str, str]], desktop_root: str | None = None) -> str:
    result = build_autonomous_project(messages, desktop_root=desktop_root, open_workspaces=True, auto_paste=True)
    spec = result["spec"]
    root_dir = result["root_dir"]
    opened = ", ".join(result["workspace_result"]["opened"]) or "-"
    pasted = ", ".join(result["workspace_result"]["pasted"]) or "-"
    failed = ", ".join(result["workspace_result"]["failed"]) or "-"
    return (
        f"Otonom proje kuruldu: {spec['project_name']}\n"
        f"Klasor: {root_dir}\n"
        f"Sablon: {spec['template']}\n"
        f"Dispatch: {'OK' if result['dispatch_ok'] else 'HATA'}\n"
        f"Acilan workspace'ler: {opened}\n"
        f"Prompt yapistirilanlar: {pasted}\n"
        f"Acilamayanlar: {failed}\n"
        "Not: macOS'ta otomatik yapistirma icin Accessibility izni gerekebilir. "
        "Gerekiyorsa her ajan klasorundeki FIRST_PROMPT.txt kullan."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Sohbetten otonom proje workspace'i kur")
    parser.add_argument("brief", nargs="*", help="Kisa proje ozeti")
    parser.add_argument("--desktop-root", default=str(Path.home() / "Desktop"))
    parser.add_argument("--no-open", action="store_true")
    parser.add_argument("--no-paste", action="store_true")
    args = parser.parse_args()

    brief_text = " ".join(args.brief).strip()
    if not brief_text:
        brief_text = "Node tabanli bir yerel AI destekli uygulama projesi"
    messages = [
        {"role": "user", "content": brief_text},
        {"role": "assistant", "content": "Projenin ana hatlarini netlestirelim."},
        {"role": "user", "content": "Yazmaya basla"},
    ]
    result = build_autonomous_project(
        messages,
        desktop_root=args.desktop_root,
        open_workspaces=not args.no_open,
        auto_paste=not args.no_paste,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()