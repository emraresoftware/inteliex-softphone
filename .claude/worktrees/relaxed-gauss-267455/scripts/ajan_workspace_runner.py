#!/usr/bin/env python3
"""
Ajan Workspace Runner — VSCode Copilot Agent için TALIMATLAR.md yürütücü
2026-03-30: İyileştirmeler — hata yönetimi, progress callback, retry mekanizması

Kullanım:
    python scripts/ajan_workspace_runner.py \
        --workspace-dir agents/workspaces/yonetici \
        --workspace-name yonetici \
        --max-steps 8
"""
from __future__ import annotations

import argparse
import asyncio
import json as _json
import logging
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

# Logging setup
LOG_DIR = Path(__file__).resolve().parents[1] / "data" / "ajan_logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    handlers=[
        logging.FileHandler(LOG_DIR / f"ajan_runner_{datetime.now().strftime('%Y%m%d')}.log"),
        logging.StreamHandler(sys.stdout),
    ],
)
LOG = logging.getLogger("ajan_runner")

# Constants
REPO_ROOT = Path(__file__).resolve().parents[1]
CODE_SUFFIXES = {".js", ".cjs", ".mjs", ".json", ".html", ".css", ".py", ".ts", ".tsx", ".jsx", ".php", ".sh"}
ARTIFACT_SUFFIXES = {".txt", ".md", ".json", ".ndjson", ".csv", ".log", ".xml", ".yaml", ".yml"}
DEFAULT_PROJECT = "projects/emarecloud_ceyiz"
MAX_PROMPT_TOKENS = 6000  # Ollama context limit guard


@dataclass
class RunStats:
    """Runner execution statistics."""
    workspace: str
    start_time: float = field(default_factory=time.time)
    attempts: int = 0
    steps_taken: int = 0
    unchecked_before: int = 0
    unchecked_after: int = 0
    code_changes: int = 0
    artifact_changes: int = 0
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    exit_code: int = 0
    exit_reason: str = ""
    
    def duration_seconds(self) -> float:
        return time.time() - self.start_time
    
    def to_dict(self) -> dict[str, Any]:
        return {
            "workspace": self.workspace,
            "duration_s": round(self.duration_seconds(), 2),
            "attempts": self.attempts,
            "steps_taken": self.steps_taken,
            "unchecked_before": self.unchecked_before,
            "unchecked_after": self.unchecked_after,
            "code_changes": self.code_changes,
            "artifact_changes": self.artifact_changes,
            "errors": self.errors,
            "warnings": self.warnings,
            "exit_code": self.exit_code,
            "exit_reason": self.exit_reason,
        }


class AjanRunnerError(Exception):
    """Base exception for ajan runner."""
    pass


class TalimatlarNotFound(AjanRunnerError):
    """TALIMATLAR.md file not found."""
    pass


class ProjectRootNotFound(AjanRunnerError):
    """Project root directory not found."""
    pass


class ModelTimeoutError(AjanRunnerError):
    """Model response timeout."""
    pass


def _estimate_tokens(text: str) -> int:
    """Rough token estimation (1 token ≈ 4 chars for Turkish/English mix)."""
    return len(text) // 4


def _truncate_prompt(prompt: str, max_tokens: int = MAX_PROMPT_TOKENS) -> str:
    """Truncate prompt if it exceeds token limit."""
    current_tokens = _estimate_tokens(prompt)
    if current_tokens <= max_tokens:
        return prompt
    
    # Keep header and task list, truncate middle
    header_end = prompt.find("Isaretlenmemis maddeler:")
    if header_end == -1:
        # No task list found, truncate from end
        chars_to_keep = max_tokens * 4
        return prompt[:chars_to_keep] + "\n\n[... truncated ...]"
    
    header = prompt[:header_end]
    task_section = prompt[header_end:]
    task_tokens = _estimate_tokens(task_section)
    header_tokens = _estimate_tokens(header)
    
    available_for_tasks = max_tokens - header_tokens - 100  # 100 token buffer
    if available_for_tasks <= 0:
        return header + "\n\n[... tum goremler truncation ...]"
    
    chars_for_tasks = available_for_tasks * 4
    return header + task_section[:chars_for_tasks] + "\n\n[... gorevler truncation ...]"


def _resolve_project_root(workspace_name: str) -> Path:
    """Resolve project root from backlog.json sprint configuration."""
    backlog_path = REPO_ROOT / "agents" / "backlog.json"
    try:
        backlog = _json.loads(backlog_path.read_text(encoding="utf-8"))
    except (OSError, _json.JSONDecodeError) as e:
        LOG.warning("backlog okunamadi, default project kullaniliyor: %s", e)
        return REPO_ROOT / DEFAULT_PROJECT

    sprints = backlog.get("sprints", {})
    
    # Find sprint with matching owner
    for sprint_id, sprint_data in sprints.items():
        tasks = sprint_data.get("tasks", [])
        for task in tasks:
            if task.get("owner") == workspace_name and task.get("status") in ("in_progress", "todo"):
                project = sprint_data.get("project")
                if project:
                    resolved = REPO_ROOT / project
                    if resolved.exists():
                        LOG.debug("Project resolved: %s (sprint=%s)", resolved, sprint_id)
                        return resolved

    # Fallback to activeSprint
    active = backlog.get("activeSprint")
    if active and active in sprints:
        project = sprints[active].get("project")
        if project:
            resolved = REPO_ROOT / project
            if resolved.exists():
                return resolved

    LOG.warning("Project root bulunamadi, default kullaniliyor: %s", workspace_name)
    return REPO_ROOT / DEFAULT_PROJECT


def _read_text(path: Path) -> str:
    """Read file with error handling."""
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="latin-1")


def _unchecked_items(text: str) -> list[str]:
    """Extract unchecked checklist items."""
    items: list[str] = []
    for line in text.splitlines():
        m = re.match(r"^\s*-\s*\[\s\]\s+(.*)$", line)
        if m:
            items.append(m.group(1).strip())
    return items


def _normalize_duplicate_checklist_lines(text: str) -> str:
    """Normalize duplicate checklist entries (keep first occurrence)."""
    lines = text.splitlines()
    normalized: list[str] = []
    index = 0

    while index < len(lines):
        current = lines[index]
        match = re.match(r"^(\s*-\s*\[)([ x])(\]\s+)(.*)$", current)
        if not match:
            normalized.append(current)
            index += 1
            continue

        item_text = match.group(4).strip()
        duplicate_block = [current]
        cursor = index + 1
        
        while cursor < len(lines):
            other = lines[cursor]
            other_match = re.match(r"^(\s*-\s*\[)([ x])(\]\s+)(.*)$", other)
            if not other_match or other_match.group(4).strip() != item_text:
                break
            duplicate_block.append(other)
            cursor += 1

        if len(duplicate_block) == 1:
            normalized.append(current)
        else:
            # Keep first occurrence (may be checked or unchecked)
            normalized.append(current)
        
        index = cursor

    return "\n".join(normalized) + ("\n" if text.endswith("\n") else "")


def _mark_items_checked(text: str, items: list[str]) -> str:
    """Mark specific checklist items as checked."""
    pending: dict[str, int] = {item: items.count(item) for item in set(items)}

    updated: list[str] = []
    for line in text.splitlines():
        match = re.match(r"^(\s*-\s*\[)([ x])(\]\s+)(.*)$", line)
        
        # Keep already checked or non-matching lines as-is
        if not match or match.group(2) == "x":
            updated.append(line)
            continue

        item_text = match.group(4).strip()
        if item_text not in pending or pending[item_text] <= 0:
            updated.append(line)
            continue

        pending[item_text] -= 1
        updated.append(f"{match.group(1)}x{match.group(3)}{match.group(4)}")

    return "\n".join(updated) + ("\n" if text.endswith("\n") else "")


def _snapshot_code_files(project_root: Path) -> dict[str, float]:
    """Snapshot code files with mtime for change detection."""
    snap: dict[str, float] = {}
    if not project_root.exists():
        return snap
    
    skip_dirs = {"node_modules", ".git", "__pycache__", ".venv", "venv", ".tox", "dist", "build", ".venv", ".eggs"}
    
    try:
        for p in project_root.rglob("*"):
            if not p.is_file():
                continue
            if p.suffix.lower() not in CODE_SUFFIXES:
                continue
            parts = p.relative_to(project_root).parts
            if any(part in skip_dirs for part in parts):
                continue
            rel = str(p.relative_to(project_root))
            try:
                snap[rel] = p.stat().st_mtime
            except OSError:
                continue
    except PermissionError as e:
        LOG.warning("Permission error scanning project: %s", e)
    
    return snap


def _detect_code_changes(before: dict[str, float], project_root: Path) -> list[str]:
    """Detect code file changes since snapshot."""
    after = _snapshot_code_files(project_root)
    changed: list[str] = []
    
    all_keys = set(before.keys()) | set(after.keys())
    for key in sorted(all_keys):
        if key not in before or key not in after:
            changed.append(key)
            continue
        if abs(after[key] - before[key]) > 0.0001:
            changed.append(key)
    
    return changed


def _snapshot_artifacts(paths: list[Path]) -> dict[str, tuple[bool, float, int]]:
    """Snapshot artifact files."""
    snapshot: dict[str, tuple[bool, float, int]] = {}
    for path in paths:
        try:
            stat = path.stat()
            snapshot[str(path)] = (True, stat.st_mtime, stat.st_size)
        except OSError:
            snapshot[str(path)] = (False, 0.0, 0)
    return snapshot


def _detect_artifact_changes(before: dict[str, tuple[bool, float, int]], paths: list[Path]) -> list[str]:
    """Detect artifact file changes since snapshot."""
    after = _snapshot_artifacts(paths)
    changed: list[str] = []

    for key in sorted(after.keys()):
        existed_before, mtime_before, size_before = before.get(key, (False, 0.0, 0))
        existed_after, mtime_after, size_after = after[key]
        
        if not existed_after:
            continue
        if not existed_before:
            changed.append(key)
            continue
        if size_after != size_before or abs(mtime_after - mtime_before) > 0.0001:
            changed.append(key)

    return changed


def _resolve_artifact_path(value: str, workspace_dir: Path) -> Path | None:
    """Resolve artifact path from checklist item text."""
    cleaned = value.strip().strip("`'\".,:;()[]{}")
    if not cleaned:
        return None

    suffix = Path(cleaned).suffix.lower()
    if suffix not in ARTIFACT_SUFFIXES:
        return None

    path = Path(cleaned)
    if not path.is_absolute():
        path = workspace_dir / path
    return path


def _expected_artifacts(unchecked: list[str], workspace_dir: Path) -> list[Path]:
    """Extract expected artifact paths from checklist items."""
    expected: list[Path] = []
    seen: set[str] = set()

    for item in unchecked:
        # Extract backtick-quoted paths
        candidates = re.findall(r"`([^`]+)`", item)
        # Extract file extensions
        candidates.extend(re.findall(r"\b[\w./-]+\.(?:txt|md|json|ndjson|csv|log|xml|yaml|yml)\b", item))

        # Special case: smoke test results
        lowered = item.lower()
        if "smoke" in lowered and ("not" in lowered or "kayda" in lowered or "sonuc" in lowered):
            candidates.append("smoke_test_results.txt")
        if "coverage" in lowered and ("rapor" in lowered or "report" in lowered):
            candidates.append("coverage_report.txt")

        for candidate in candidates:
            path = _resolve_artifact_path(candidate, workspace_dir)
            if path is None:
                continue
            key = str(path)
            if key in seen:
                continue
            seen.add(key)
            expected.append(path)

    return expected


def _build_prompt(
    workspace_name: str,
    workspace_dir: Path,
    talimatlar_path: Path,
    unchecked: list[str],
    retry: bool = False,
    attempt: int = 1,
) -> str:
    """Build AI prompt from TALIMATLAR checklist items."""
    joined = "\n".join(f"- [ ] {x}" for x in unchecked)
    lowered = "\n".join(unchecked).lower()
    
    project_root = _resolve_project_root(workspace_name)
    project_path = str(project_root)
    
    # Language/framework specific hints
    command_hint = ""
    if any(token in lowered for token in ("npm", "npm test", "jest", "node", "npx")):
        command_hint = (
            f"5) npm/jest/node komutlari icin: `cd {project_path} && <komut>`\n"
            "6) Python ve npm paketlerini karistirma; once npm komutlarini dene.\n"
            "7) Artifact dosyasini komut ciktisina gore doldur.\n"
        )
    elif any(token in lowered for token in ("python", "pytest", "uvicorn", "fastapi", "pip")):
        command_hint = (
            f"5) Python komutlari icin: `cd {project_path} && /Users/emre/Dergah/.venv/bin/python <script.py>`\n"
            "6) Uvicorn icin: `/Users/emre/Dergah/.venv/bin/python -m uvicorn ...`\n"
            "7) Artifact dosyasini komut ciktisina gore doldur.\n"
        )
    elif any(token in lowered for token in ("php", "artisan", "laravel", "composer")):
        command_hint = (
            f"5) PHP/Laravel komutlari icin: `cd {project_path} && php artisan <komut>`\n"
            "6) Migration: `php artisan migrate`\n"
            "7) Test: `php artisan test` veya `./vendor/bin/phpunit`\n"
        )

    # Existing files hint (limited to avoid token overflow)
    existing_files_hint = ""
    if project_root.exists():
        skip = {"node_modules", ".git", "__pycache__", ".venv", "venv", ".tox", "dist", "build"}
        file_list = []
        try:
            for p in sorted(project_root.rglob("*")):
                if not p.is_file():
                    continue
                parts = p.relative_to(project_root).parts
                if any(part in skip for part in parts):
                    continue
                file_list.append(str(p.relative_to(project_root)))
                if len(file_list) >= 30:  # Limit file list
                    break
        except PermissionError:
            pass
        
        if file_list:
            existing_files_hint = (
                f"\nProje dosyalari (`{project_path}`):\n"
                + "\n".join(f"  - {f}" for f in file_list)
                + "\n"
            )

    # Retry specific instructions
    extra = ""
    if retry:
        extra = (
            "8) Onceki denemede eksik kaldi. Simdi tamamla.\n"
            "9) Checklist maddelerini '- [x]' olarak isaretle.\n"
            "10) SADECE '- [ ]' ile baslayan maddeleri isaretle.\n"
        )

    base_prompt = (
        "Bu bir workspace-ajan gorevidir.\n"
        "Asagidaki TALIMATLAR.md dosyasindaki isaretlenmemis maddeleri uygula.\n\n"
        f"Ajan: {workspace_name}\n"
        f"Workspace: {workspace_dir}\n"
        f"Proje dizini: {project_path}\n"
        f"Talimat dosyasi: {talimatlar_path}\n"
        f"{existing_files_hint}"
        "Kurallar:\n"
        "1) Dosyalari SADECE proje dizininde olustur/duzenle.\n"
        "2) Mevcut dosyalari silme veya bos birakma. Sadece gerekli satirlari degistir.\n"
        "3) Tamamlanan maddeleri '- [x]' olarak isaretle.\n"
        "4) Zaten '- [x]' olanlari degistirme.\n"
        "5) Is bitince kisa durum ozeti yaz.\n"
        f"{command_hint}"
        f"{extra}\n"
        "Isaretlenmemis maddeler:\n"
        f"{joined}\n"
    )
    
    return _truncate_prompt(base_prompt)


async def _run_ajan(
    workspace_name: str,
    workspace_dir: Path,
    talimatlar_path: Path,
    max_steps: int,
    stats: RunStats,
    progress_callback: Callable[[str], None] | None = None,
) -> int:
    """Execute ajan with TALIMATLAR checklist items."""
    
    def _progress(msg: str) -> None:
        LOG.info(msg)
        if progress_callback:
            progress_callback(msg)
    
    def _update_status(status: str, task: str | None = None) -> None:
        """Update agent status in SQLite database."""
        try:
            import dervis_mesajlasma as dm
            dm.update_agent_status(workspace_name, status, task)
        except Exception as e:
            LOG.debug("Status update failed: %s", e)
    
    try:
        # Update status: working
        _update_status("working", f"max_steps={max_steps}")
        
        # Read TALIMATLAR
        text_before = _read_text(talimatlar_path)
        unchecked_before = _unchecked_items(text_before)
        stats.unchecked_before = len(unchecked_before)
        
        if not unchecked_before:
            _progress("unchecked=0, skip")
            _update_status("idle")
            stats.exit_reason = "no_unchecked_items"
            return 0
        
        _progress(f"workspace={workspace_name} unchecked={len(unchecked_before)}")
        
        # Import dervis_core (lazy load)
        try:
            import dervis_core
        except ImportError as e:
            stats.errors.append(f"dervis_core import hatasi: {e}")
            LOG.error("dervis_core import failed: %s", e)
            _update_status("error", f"import_error: {e}")
            return 10
        
        project_root = _resolve_project_root(workspace_name)
        if not project_root.exists():
            stats.errors.append(f"Project root bulunamadi: {project_root}")
            LOG.error("Project root not found: %s", project_root)
            _update_status("error", "project_not_found")
            return 11
        
        _progress(f"project_root={project_root}")
        
        # Snapshots
        code_before = _snapshot_code_files(project_root)
        expected_artifacts = _expected_artifacts(unchecked_before, workspace_dir)
        artifact_before = _snapshot_artifacts(expected_artifacts)
        
        if expected_artifacts:
            _progress(f"expected_artifacts={len(expected_artifacts)}")
            for path in expected_artifacts:
                _progress(f"  - {path}")
        
        # Main execution loop (max 2 attempts)
        unchecked_prev = unchecked_before
        for attempt in (1, 2):
            stats.attempts += 1
            _progress(f"=== Attempt {attempt} ===")
            
            # Update status with progress
            _update_status("working", f"attempt={attempt} remaining={len(unchecked_prev)}")
            
            prompt = _build_prompt(
                workspace_name,
                workspace_dir,
                talimatlar_path,
                unchecked_prev,
                retry=(attempt > 1),
                attempt=attempt,
            )
            
            _progress(f"Prompt tokens ~{_estimate_tokens(prompt)}")
            
            # Run AI goal
            try:
                start = time.time()
                answer = await asyncio.wait_for(
                    dervis_core.run_goal(prompt, max_steps=max_steps, echo=False),
                    timeout=300,  # 5 minute timeout
                )
                stats.steps_taken += max_steps
                elapsed = time.time() - start
                _progress(f"Model response: {elapsed:.1f}s")
            except asyncio.TimeoutError:
                stats.errors.append(f"Attempt {attempt}: Model timeout (>300s)")
                LOG.error("Model timeout on attempt %d", attempt)
                continue
            except Exception as e:
                stats.errors.append(f"Attempt {attempt}: {type(e).__name__}: {e}")
                LOG.error("Model error on attempt %d: %s", attempt, e)
                continue
            
            # Check TALIMATLAR changes
            text_after = _read_text(talimatlar_path)
            
            # Normalize duplicates
            normalized_text_after = _normalize_duplicate_checklist_lines(text_after)
            if normalized_text_after != text_after:
                talimatlar_path.write_text(normalized_text_after, encoding="utf-8")
                text_after = normalized_text_after
                _progress("Duplicate checklist entries normalized")
            
            # Check artifact changes
            changed_artifacts = _detect_artifact_changes(artifact_before, expected_artifacts)
            
            # Sync checklist if artifacts changed
            if changed_artifacts:
                _progress(f"Artifacts changed: {len(changed_artifacts)}")
                synced = _mark_items_checked(text_after, unchecked_prev)
                synced = _normalize_duplicate_checklist_lines(synced)
                if synced != text_after:
                    talimatlar_path.write_text(synced, encoding="utf-8")
                    text_after = synced
                    _progress("Checklist synced with artifacts")
            
            unchecked_after = _unchecked_items(text_after)
            stats.unchecked_after = len(unchecked_after)
            _progress(f"unchecked_after_attempt_{attempt}={len(unchecked_after)}")
            
            # Success: items completed
            if len(unchecked_after) < len(unchecked_prev):
                code_changes = _detect_code_changes(code_before, project_root)
                stats.code_changes = len(code_changes)
                
                if code_changes:
                    _progress(f"Code changes detected: {len(code_changes)}")
                    for path in code_changes[:10]:
                        _progress(f"  - {path}")
                
                if changed_artifacts:
                    _progress(f"Artifact changes: {len(changed_artifacts)}")
                
                stats.exit_reason = "tasks_completed"
                return 0
            
            # Failure: no progress after max attempts
            if attempt == 2:
                stats.exit_reason = "max_attempts_reached"
                stats.exit_code = 2
                return 2
        
        # Should not reach here, but safety return
        return 3
        
    except Exception as e:
        stats.errors.append(f"Fatal: {type(e).__name__}: {e}")
        LOG.exception("Fatal error in _run_ajan")
        return 99


def main() -> int:
    """Main entry point for ajan workspace runner."""
    parser = argparse.ArgumentParser(
        description="Workspace TALIMATLAR icin AI runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ornekler:
    python scripts/ajan_workspace_runner.py \\
        --workspace-dir agents/workspaces/yonetici \\
        --workspace-name yonetici \\
        --max-steps 8
        
    # Dry-run (sadece analiz)
    python scripts/ajan_workspace_runner.py \\
        --workspace-dir agents/workspaces/api-dev \\
        --workspace-name api-dev \\
        --dry-run
        """,
    )
    parser.add_argument("--workspace-dir", required=True, help="Workspace dizin yolu")
    parser.add_argument("--workspace-name", required=True, help="Ajan adi")
    parser.add_argument("--max-steps", type=int, default=8, help="Maksimum AI adimi (varsayilan: 8)")
    parser.add_argument("--dry-run", action="store_true", help="TALIMATLAR analiz et, calistirma")
    parser.add_argument("--verbose", "-v", action="store_true", help="Ayrintili log")
    
    args = parser.parse_args()
    
    if args.verbose:
        LOG.setLevel(logging.DEBUG)
    
    workspace_dir = Path(args.workspace_dir).resolve()
    talimatlar_path = workspace_dir / "TALIMATLAR.md"
    
    if not talimatlar_path.exists():
        LOG.error("TALIMATLAR.md bulunamadi: %s", talimatlar_path)
        return 1
    
    stats = RunStats(workspace=args.workspace_name)
    
    # Dry-run: just analyze
    if args.dry_run:
        text = _read_text(talimatlar_path)
        unchecked = _unchecked_items(text)
        artifacts = _expected_artifacts(unchecked, workspace_dir)
        project = _resolve_project_root(args.workspace_name)
        
        print("=" * 60)
        print(f"DRY-RUN ANALYZ: {args.workspace_name}")
        print("=" * 60)
        print(f"TALIMATLAR: {talimatlar_path}")
        print(f"Project: {project}")
        print(f"Unchecked items: {len(unchecked)}")
        print(f"Expected artifacts: {len(artifacts)}")
        print()
        print("Items:")
        for item in unchecked:
            print(f"  - [ ] {item}")
        print()
        print("Artifacts:")
        for path in artifacts:
            print(f"  - {path}")
        print("=" * 60)
        return 0
    
    # Actual run
    LOG.info("Starting ajan runner: %s", args.workspace_name)
    
    exit_code = asyncio.run(
        _run_ajan(
            workspace_name=args.workspace_name,
            workspace_dir=workspace_dir,
            talimatlar_path=talimatlar_path,
            max_steps=max(1, args.max_steps),
            stats=stats,
        )
    )
    
    stats.exit_code = exit_code
    LOG.info("Ajan runner finished: %s exit=%d reason=%s", 
             args.workspace_name, exit_code, stats.exit_reason)
    
    # Write stats to log
    stats_log = LOG_DIR / f"stats_{datetime.now().strftime('%Y%m%d')}.jsonl"
    try:
        with stats_log.open("a", encoding="utf-8") as f:
            f.write(_json.dumps(stats.to_dict()) + "\n")
    except Exception as e:
        LOG.warning("Stats log yazilamadi: %s", e)
    
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
