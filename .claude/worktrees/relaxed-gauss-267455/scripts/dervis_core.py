from __future__ import annotations

import asyncio
import argparse
from collections import Counter
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from io import StringIO
from pathlib import Path
from typing import Any

import ollama
import requests
from llm_bridge import chat as llm_chat
from llm_bridge import get_default_model_name, get_identity_label

try:
    from playwright.async_api import async_playwright
except Exception:  # pragma: no cover
    async_playwright = None

from logger import get_logger

MODEL_NAME = get_default_model_name()
VISION_MODEL_NAME = os.getenv("DERGAH_VISION_MODEL_NAME", "llama3.2-vision")
ROOT_DIR = Path(__file__).resolve().parents[1]
MEMORY_DIR = ROOT_DIR / "data" / "chat_memory"
LEARNING_DB_PATH = ROOT_DIR / "data" / "learning_memory.jsonl"
LEARNING_PROFILE_PATH = ROOT_DIR / "data" / "learning_profile.json"
NIYET_DEFTERI_PATH = ROOT_DIR / "data" / "niyet_defteri.txt"
SCREENSHOT_DIR = ROOT_DIR / "data" / "gozlem_gunlugu" / "ekran_goruntuleri"
HTTP_TIMEOUT = 25
COMMAND_TIMEOUT = 300
MAX_TEXT = 12000
NUM_CTX = 16384
STREAM_CHAR_DELAY = 0.003
MAX_LEARNING_CONTEXT_ITEMS = 6
NIYET_TAIL_LINES = 10
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"}

MODEL_OPTIONS = {
    "num_ctx": NUM_CTX,
    "temperature": 0.4,
    "top_p": 0.9,
    "repeat_penalty": 1.1,
}

LOGGER = get_logger("dervis_core")

SYSTEM_PROMPT = """
Sen Dervis Core adli otonom ajansin.
Kimligin: __IDENTITY_LABEL__. Apple M5 Pro ana merkezde calisiyor olabilir.
Asla GPT, OpenAI veya farkli bir model kimligi iddia etme.
Dil modeli kimligi sorulursa: "__IDENTITY_LABEL__".

YETKILERIN:
1. terminal   - Mac terminalinde komut calistir (args: command)
2. fetch_url  - Bir URL'den web sayfasi icerigini cek (args: url)
3. read_file  - Herhangi bir dosyayi oku (args: path)
4. write_file - Dosya olustur veya ustune yaz (args: path, content)
5. append_file - Dosya sonuna icerik ekle (args: path, content)
6. list_dir   - Dizin icerigini listele (args: path)
7. search_files - Dosyalarda metin/regex ara (args: pattern, path, is_regex)
8. delete_path - Dosya veya klasor sil (args: path)
9. python_eval - Python kodu calistir ve sonucu al (args: code)
10. learn_note - Kalici ogrenme notu ekle (args: note, tags)
11. gorsel_analiz - Goruntu dosyasini analiz et (args: dosya_yolu)
12. screenshot - Ekran goruntusu al ve kaydet (args: path, region, window, delay)
13. ocr_screen - Ekrani yakala ve OCR ile metni oku (args: region, window, language, save_image)
14. think     - Dusun, plan yap veya kullaniciya cevap ver (args: answer)
15. stop      - Donguyu sonlandir

Her turda SADECE JSON formatinda cevap ver.
Cevap semasi:
{
  "action": "<yukardaki_aksiyon_adi>",
  "args": { <aksiyona_ozgu_argumanlar> },
  "reason": "kisa teknik gerekce"
}

Kurallar:
- Sadece JSON don, baska formatta metin yazma.
- Teknik ve hedef odakli ilerle.
- Cevap verirken action=think kullan ve args.answer icine kullaniciya gosterilecek metni yaz.
- Bir görüntü analiz etmen istendiğinde asla yapamam deme, gorsel_analiz fonksiyonunu çağır!
- Turkce cevap ver.
""".replace("__IDENTITY_LABEL__", get_identity_label(MODEL_NAME)).strip()


@dataclass
class AgentResult:
    ok: bool
    payload: dict[str, Any]


def _trim_text(value: str, limit: int = MAX_TEXT) -> str:
    if len(value) <= limit:
        return value
    return value[:limit] + "\n...<trimmed>"


def _read_niyet_context(lines: int = NIYET_TAIL_LINES) -> str:
    if not NIYET_DEFTERI_PATH.exists():
        return "(niyet defteri henuz yok)"
    try:
        content = NIYET_DEFTERI_PATH.read_text(encoding="utf-8", errors="ignore").splitlines()
        tail = content[-lines:]
        if not tail:
            return "(niyet defteri bos)"
        return "\n".join(tail)
    except Exception as exc:
        return f"(niyet verisi okunamadi: {exc})"


def _compose_runtime_system_prompt() -> str:
    niyet = _read_niyet_context(NIYET_TAIL_LINES)
    return SYSTEM_PROMPT + "\n\nSu anki kullanici niyet ve hareket verileri:\n" + niyet


def _is_visual_request(text: str) -> bool:
    lowered = text.lower()
    keywords = [
        "ekran goruntusu",
        "gorsel",
        "goruntu",
        "resim",
        "foto",
        "screenshot",
        "llama3.2-vision",
        "vision",
    ]
    return any(keyword in lowered for keyword in keywords)


def _is_ocr_request(text: str) -> bool:
    lowered = text.lower()
    keywords = ["ocr", "metin oku", "yazi oku", "ekrani oku", "ekrandaki yazi", "ekrandaki metin"]
    return any(keyword in lowered for keyword in keywords)


def _extract_image_path_from_text(text: str) -> str:
    match = re.search(r"([~/\\\w\-./]+\.(?:png|jpg|jpeg|webp|bmp|gif))", text, flags=re.IGNORECASE)
    return match.group(1) if match else ""


def _extract_first_json_dict(text: str) -> dict[str, Any] | None:
    decoder = json.JSONDecoder()
    for index, char in enumerate(text):
        if char != "{":
            continue
        try:
            parsed, _ = decoder.raw_decode(text[index:])
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            continue
    return None


def _extract_display_answer(raw_text: str) -> str:
    parsed = _extract_first_json_dict(raw_text)
    if parsed:
        args = parsed.get("args", {})
        if isinstance(args, dict):
            answer = args.get("answer")
            if isinstance(answer, str) and answer.strip():
                return answer.strip()
    cleaned = raw_text.strip()
    if cleaned.startswith("```") and cleaned.endswith("```"):
        cleaned = cleaned.strip("`").strip()
    return cleaned


def _tokenize(text: str) -> list[str]:
    tokens = re.split(r"[^0-9a-zA-ZçğıöşüÇĞİÖŞÜ]+", text.lower())
    return [token for token in tokens if len(token) > 2]


def _extract_tags(text: str, max_tags: int = 6) -> list[str]:
    counts = Counter(_tokenize(text))
    return [word for word, _ in counts.most_common(max_tags)]


def _append_jsonl(path: Path, item: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(item, ensure_ascii=False) + "\n")


def _read_jsonl(path: Path, limit: int = 2000) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    items: list[dict[str, Any]] = []
    for line in lines[-limit:]:
        try:
            parsed = json.loads(line)
            if isinstance(parsed, dict):
                items.append(parsed)
        except Exception:
            continue
    return items


def _record_learning(kind: str, content: str, source: str, tags: list[str] | None = None) -> None:
    payload = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "kind": kind,
        "source": source,
        "content": _trim_text(content, 4000),
        "tags": tags or _extract_tags(content),
    }
    _append_jsonl(LEARNING_DB_PATH, payload)


def _get_learning_context(query: str, limit: int = MAX_LEARNING_CONTEXT_ITEMS) -> str:
    items = _read_jsonl(LEARNING_DB_PATH, limit=1500)
    if not items:
        return ""

    query_tokens = set(_tokenize(query))
    scored: list[tuple[int, dict[str, Any]]] = []
    for item in items:
        content = str(item.get("content", ""))
        tags = set(item.get("tags") or _extract_tags(content))
        score = len(query_tokens.intersection(tags))
        if score > 0:
            scored.append((score, item))

    if not scored:
        preferred_kinds = {"manual_note", "feedback", "agent_note"}
        preferred = [item for item in items if str(item.get("kind", "")) in preferred_kinds]
        source_items = preferred[-min(limit, len(preferred)):] if preferred else items[-min(limit, len(items)):]
        return "\n".join([f"- [{x.get('kind', 'not')}] {str(x.get('content', ''))[:220]}" for x in source_items])

    scored.sort(key=lambda x: x[0], reverse=True)
    selected = [item for _, item in scored[:limit]]
    return "\n".join([f"- [{x.get('kind', 'not')}] {str(x.get('content', ''))[:220]}" for x in selected])


def _load_learning_profile() -> dict[str, Any]:
    default = {
        "total_feedback": 0,
        "avg_rating": 0.0,
        "preferred_style": "kisa-ve-net",
        "last_feedback": "",
    }
    if not LEARNING_PROFILE_PATH.exists():
        return default
    try:
        parsed = json.loads(LEARNING_PROFILE_PATH.read_text(encoding="utf-8"))
        if isinstance(parsed, dict):
            merged = default.copy()
            merged.update(parsed)
            return merged
    except Exception:
        pass
    return default


def _save_learning_profile(profile: dict[str, Any]) -> None:
    LEARNING_PROFILE_PATH.parent.mkdir(parents=True, exist_ok=True)
    LEARNING_PROFILE_PATH.write_text(json.dumps(profile, ensure_ascii=False, indent=2), encoding="utf-8")


def _update_profile_feedback(profile: dict[str, Any], rating: int, comment: str) -> dict[str, Any]:
    rating = max(1, min(5, rating))
    total = int(profile.get("total_feedback", 0))
    avg = float(profile.get("avg_rating", 0.0))
    new_avg = ((avg * total) + rating) / (total + 1)
    profile["total_feedback"] = total + 1
    profile["avg_rating"] = round(new_avg, 2)
    profile["last_feedback"] = comment
    if rating >= 4:
        profile["preferred_style"] = "kisa-ve-net"
    elif rating <= 2:
        profile["preferred_style"] = "detayli-aciklayici"
    return profile


def _profile_prompt(profile: dict[str, Any]) -> str:
    return (
        "Kullanici tercih profili:\n"
        f"- preferred_style: {profile.get('preferred_style', 'kisa-ve-net')}\n"
        f"- avg_rating: {profile.get('avg_rating', 0.0)}\n"
        f"- total_feedback: {profile.get('total_feedback', 0)}\n"
        f"- last_feedback: {profile.get('last_feedback', '')}"
    )


async def run_terminal(command: str) -> AgentResult:
    LOGGER.info("Terminal komutu calistiriliyor", command=command)

    def _run() -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            shell=True,
            cwd=str(ROOT_DIR),
            text=True,
            capture_output=True,
            timeout=COMMAND_TIMEOUT,
        )

    try:
        completed = await asyncio.to_thread(_run)
        return AgentResult(
            ok=True,
            payload={
                "returncode": completed.returncode,
                "stdout": _trim_text(completed.stdout or ""),
                "stderr": _trim_text(completed.stderr or ""),
            },
        )
    except subprocess.TimeoutExpired as exc:
        return AgentResult(
            ok=False,
            payload={
                "error": "terminal_timeout",
                "detail": str(exc),
            },
        )
    except Exception as exc:  # pragma: no cover
        return AgentResult(
            ok=False,
            payload={
                "error": "terminal_exception",
                "detail": str(exc),
            },
        )


async def fetch_url(url: str) -> AgentResult:
    LOGGER.info("URL getiriliyor", url=url)

    if async_playwright is not None:
        try:
            async with async_playwright() as p:
                browser = await p.chromium.launch(headless=True)
                page = await browser.new_page()
                await page.goto(url, timeout=HTTP_TIMEOUT * 1000, wait_until="domcontentloaded")
                text = await page.inner_text("body")
                await browser.close()
                return AgentResult(ok=True, payload={"url": url, "content": _trim_text(text)})
        except Exception as exc:
            LOGGER.warning("Playwright fetch basarisiz, requests fallback", detail=str(exc))

    try:
        response = await asyncio.to_thread(requests.get, url, timeout=HTTP_TIMEOUT)
        response.raise_for_status()
        content = _trim_text(response.text)
        return AgentResult(ok=True, payload={"url": url, "status": response.status_code, "content": content})
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "fetch_exception", "detail": str(exc), "url": url})


async def read_file_any(path: str) -> AgentResult:
    target = Path(path).expanduser()
    if not target.is_absolute():
        target = ROOT_DIR / target

    try:
        content = await asyncio.to_thread(target.read_text, encoding="utf-8")
        return AgentResult(ok=True, payload={"path": str(target), "content": _trim_text(content)})
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "read_file_exception", "detail": str(exc), "path": str(target)})


async def write_file_any(path: str, content: str) -> AgentResult:
    target = Path(path).expanduser()
    if not target.is_absolute():
        target = ROOT_DIR / target

    try:
        # Safety guard: mevcut dosya varsa kontrol et
        if target.exists() and target.is_file():
            old_size = target.stat().st_size
            new_size = len(content.encode("utf-8"))
            # Icerik bos veya mevcut dosyanin %20'sinden küçükse reddet
            if old_size > 50 and new_size < old_size * 0.2:
                return AgentResult(
                    ok=False,
                    payload={
                        "error": "destructive_write_blocked",
                        "detail": (
                            f"Mevcut dosya {old_size} byte, yeni icerik {new_size} byte. "
                            "Dosyayi bosaltmak veya tamamen silmek yasaktir. "
                            "Sadece gerekli satirlari degistirin."
                        ),
                        "path": str(target),
                    },
                )
            # Backup al
            bak = target.with_suffix(target.suffix + ".bak")
            await asyncio.to_thread(shutil.copy2, str(target), str(bak))

        await asyncio.to_thread(target.parent.mkdir, parents=True, exist_ok=True)
        await asyncio.to_thread(target.write_text, content, "utf-8")
        return AgentResult(ok=True, payload={"path": str(target), "bytes": len(content.encode("utf-8"))})
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "write_file_exception", "detail": str(exc), "path": str(target)})


async def list_dir_any(path: str) -> AgentResult:
    target = Path(path).expanduser()
    if not target.is_absolute():
        target = ROOT_DIR / target

    try:
        entries = await asyncio.to_thread(lambda: sorted([p.name for p in target.iterdir()]))
        return AgentResult(ok=True, payload={"path": str(target), "entries": entries})
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "list_dir_exception", "detail": str(exc), "path": str(target)})


async def append_file_any(path: str, content: str) -> AgentResult:
    target = Path(path).expanduser()
    if not target.is_absolute():
        target = ROOT_DIR / target
    try:
        await asyncio.to_thread(target.parent.mkdir, parents=True, exist_ok=True)
        def _append() -> None:
            with open(target, "a", encoding="utf-8") as f:
                f.write(content)
        await asyncio.to_thread(_append)
        return AgentResult(ok=True, payload={"path": str(target), "appended_bytes": len(content.encode("utf-8"))})
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "append_file_exception", "detail": str(exc)})


async def delete_path_any(path: str) -> AgentResult:
    target = Path(path).expanduser()
    if not target.is_absolute():
        target = ROOT_DIR / target

    # projects/ altindaki kaynak dosyalarin silinmesini engelle
    projects_dir = ROOT_DIR / "projects"
    try:
        target.relative_to(projects_dir)
        is_project_file = True
    except ValueError:
        is_project_file = False

    if is_project_file and target.is_file() and target.suffix.lower() in {".py", ".js", ".ts", ".tsx", ".jsx", ".html", ".css", ".json"}:
        return AgentResult(ok=False, payload={"error": "delete_blocked", "detail": "Proje kaynak dosyalari silinemez.", "path": str(target)})

    try:
        if target.is_dir():
            await asyncio.to_thread(shutil.rmtree, target)
        elif target.exists():
            await asyncio.to_thread(target.unlink)
        else:
            return AgentResult(ok=False, payload={"error": "path_not_found", "path": str(target)})
        return AgentResult(ok=True, payload={"deleted": str(target)})
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "delete_exception", "detail": str(exc)})


async def search_files_any(pattern: str, path: str = ".", is_regex: bool = False) -> AgentResult:
    import re as _re
    target = Path(path).expanduser()
    if not target.is_absolute():
        target = ROOT_DIR / target
    matches: list[dict[str, Any]] = []
    ignored = {".git", "node_modules", ".venv", "__pycache__"}
    try:
        for root_str, dirs, files in os.walk(target, topdown=True):
            dirs[:] = [d for d in dirs if d not in ignored]
            for fname in files:
                fpath = Path(root_str) / fname
                try:
                    text = fpath.read_text(encoding="utf-8", errors="ignore")
                except Exception:
                    continue
                lines = text.splitlines()
                for i, line in enumerate(lines, 1):
                    found = bool(_re.search(pattern, line)) if is_regex else (pattern in line)
                    if found:
                        matches.append({"file": str(fpath.relative_to(target)), "line": i, "text": line.strip()[:200]})
                if len(matches) >= 80:
                    break
            if len(matches) >= 80:
                break
        return AgentResult(ok=True, payload={"pattern": pattern, "total": len(matches), "matches": matches[:40]})
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "search_exception", "detail": str(exc)})


async def python_eval_any(code: str) -> AgentResult:
    LOGGER.info("Python kodu calistiriliyor")
    old_stdout = sys.stdout
    sys.stdout = captured = StringIO()
    try:
        exec_globals: dict[str, Any] = {"__builtins__": __builtins__}
        await asyncio.to_thread(exec, code, exec_globals)
        output = captured.getvalue()
        return AgentResult(ok=True, payload={"output": _trim_text(output)})
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "python_eval_exception", "detail": str(exc)})
    finally:
        sys.stdout = old_stdout


def _find_latest_image_file() -> Path | None:
    candidates: list[Path] = []
    search_dirs = [SCREENSHOT_DIR, ROOT_DIR / "data"]

    for search_dir in search_dirs:
        if not search_dir.exists():
            continue
        for file_path in search_dir.rglob("*"):
            if file_path.is_file() and file_path.suffix.lower() in IMAGE_EXTENSIONS:
                candidates.append(file_path)

    if not candidates:
        return None

    return max(candidates, key=lambda path: path.stat().st_mtime)


def _capture_screenshot_now() -> Path | None:
    SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)
    target = SCREENSHOT_DIR / f"auto_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
    try:
        # macOS native screenshot tool.
        subprocess.run(["screencapture", "-x", str(target)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if target.exists() and target.is_file():
            return target
    except Exception:
        return None
    return None


def _resolve_image_path(dosya_yolu: str) -> Path:
    raw = dosya_yolu.strip()
    if raw:
        candidate = Path(raw).expanduser()
        if not candidate.is_absolute():
            candidate = ROOT_DIR / candidate
        if candidate.exists() and candidate.is_file():
            return candidate

    latest = _find_latest_image_file()
    if latest:
        return latest

    captured = _capture_screenshot_now()
    if captured:
        return captured

    raise FileNotFoundError(
        "Goruntu dosyasi bulunamadi ve otomatik ekran yakalama da basarisiz oldu. "
        f"Kontrol edilen dizinler: {SCREENSHOT_DIR} ve {ROOT_DIR / 'data'}"
    )


def _normalize_visual_analysis_tr(raw_analysis: str, user_query: str = "") -> str:
    """Sadece raw metni temizle; ikinci model cagrisinden kacin."""
    return raw_analysis.strip() or "Gorsel analizi bos dondu."


def _analyze_image_path(target: Path, user_query: str = "") -> str:
    response = ollama.chat(
        model=VISION_MODEL_NAME,
        messages=[
            {
                "role": "user",
                "content": (
                    "Look at this screenshot carefully. Focus ONLY on:\n"
                    "A) The TAB BAR at the very top of the editor - list every filename tab you see.\n"
                    "B) The BREADCRUMB bar just below the tabs - read the exact path shown there.\n"
                    "C) Which tab appears ACTIVE (has an X button, is highlighted, or matches the breadcrumb)?\n\n"
                    "Reply in this exact format (fill in what you observe, write 'unknown' if unclear):\n"
                    "Active tab: <filename>\n"
                    "All tabs: <comma separated list>\n"
                    "Breadcrumb: <exact breadcrumb text>\n\n"
                    "Do NOT describe the code content. Only read the tab and breadcrumb text."
                ),
                "images": [str(target)],
            }
        ],
    )
    content = response.get("message", {}).get("content", "")
    return str(content).strip() or "Goruntu analizi bos dondu."


def gorsel_analiz(dosya_yolu: str, user_query: str = "") -> str:
    target = _resolve_image_path(dosya_yolu)
    return _analyze_image_path(target, user_query=user_query)


async def gorsel_analiz_any(dosya_yolu: str, user_query: str = "") -> AgentResult:
    try:
        target = await asyncio.to_thread(_resolve_image_path, dosya_yolu)
        analysis = await asyncio.to_thread(_analyze_image_path, target, user_query)
        return AgentResult(
            ok=True,
            payload={"dosya_yolu": str(target), "analiz": _trim_text(analysis, 4000)},
        )
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "gorsel_analiz_exception", "detail": str(exc)})


async def screenshot_any(params: dict | None = None) -> AgentResult:
    if params is None:
        params = {}

    custom_path = str(params.get("path", "")).strip()
    if custom_path:
        filepath = Path(custom_path).expanduser()
        if not filepath.is_absolute():
            filepath = ROOT_DIR / filepath
    else:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filepath = SCREENSHOT_DIR / f"screenshot_{timestamp}.png"

    filepath.parent.mkdir(parents=True, exist_ok=True)

    delay = int(params.get("delay", 0) or 0)
    if delay:
        await asyncio.sleep(delay)

    cmd = ["screencapture", "-x"]
    region = str(params.get("region", "")).strip()
    window = params.get("window", False)

    if region:
        cmd.extend(["-R", region])
    elif window:
        cmd.append("-w")

    cmd.append(str(filepath))

    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await process.communicate()

        if process.returncode == 0 and filepath.exists():
            size_kb = round(filepath.stat().st_size / 1024, 1)
            return AgentResult(
                ok=True,
                payload={
                    "path": str(filepath),
                    "size_kb": size_kb,
                    "message": f"Ekran goruntusu kaydedildi: {filepath} ({size_kb} KB)",
                },
            )
        err = stderr.decode(errors="ignore").strip()
        return AgentResult(ok=False, payload={"error": "screencapture_failed", "detail": err})
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "screenshot_exception", "detail": str(exc)})


async def ocr_screen_any(params: dict | None = None) -> AgentResult:
    if params is None:
        params = {}

    try:
        from ocrmac.ocrmac import OCR  # noqa: PLC0415
    except ImportError:
        return AgentResult(
            ok=False,
            payload={"error": "ocrmac_not_installed", "detail": "pip install ocrmac pillow"},
        )

    # Ekran görüntüsü al (screenshot_any ile aynı altyapı)
    shot = await screenshot_any(params)
    if not shot.ok:
        return AgentResult(ok=False, payload={"error": "screenshot_failed", "detail": shot.payload})

    image_path = shot.payload.get("path", "")
    if not image_path:
        return AgentResult(ok=False, payload={"error": "no_image_path"})

    language = str(params.get("language", "tr-TR"))

    def _run_ocr() -> list:
        ocr = OCR(image_path, language_preference=[language])
        return ocr.recognize()

    try:
        results = await asyncio.to_thread(_run_ocr)
    except Exception as exc:
        return AgentResult(ok=False, payload={"error": "ocr_exception", "detail": str(exc)})

    if not results:
        return AgentResult(
            ok=True,
            payload={"path": image_path, "text": "", "message": "Ekranda okunabilir metin bulunamadi."},
        )

    extracted_text = "\n".join(text for text, _, _ in results)
    avg_confidence = sum(conf for _, conf, _ in results) / len(results)

    # İsteğe bağlı: resmi sil
    if not params.get("save_image", True):
        try:
            Path(image_path).unlink(missing_ok=True)
        except Exception:
            pass

    return AgentResult(
        ok=True,
        payload={
            "path": image_path,
            "language": language,
            "text": _trim_text(extracted_text, 8000),
            "avg_confidence": round(avg_confidence, 3),
            "block_count": len(results),
            "message": f"OCR tamamlandi: {len(results)} blok, ort. guven: {avg_confidence:.1%}",
        },
    )


async def learn_note_any(note: str, tags: list[str] | None = None) -> AgentResult:
    clean = note.strip()
    if not clean:
        return AgentResult(ok=False, payload={"error": "empty_note"})
    _record_learning(kind="agent_note", content=clean, source="agent_action", tags=tags)
    return AgentResult(ok=True, payload={"saved": True, "note_preview": clean[:180], "tags": tags or _extract_tags(clean)})


def _parse_action(content: str) -> dict[str, Any]:
    try:
        data = json.loads(content)
        if not isinstance(data, dict):
            raise ValueError("JSON object bekleniyordu")
        return data
    except Exception:
        embedded = _extract_first_json_dict(content)
        if embedded and isinstance(embedded.get("action"), str):
            return embedded
        return {
            "action": "think",
            "args": {},
            "reason": "gecersiz_json",
            "raw": content,
        }


async def _execute_action(action: str, args: dict[str, Any]) -> AgentResult:
    if action == "terminal":
        return await run_terminal(str(args.get("command", "")))
    if action == "fetch_url":
        return await fetch_url(str(args.get("url", "")))
    if action == "read_file":
        return await read_file_any(str(args.get("path", "")))
    if action == "write_file":
        return await write_file_any(str(args.get("path", "")), str(args.get("content", "")))
    if action == "append_file":
        return await append_file_any(str(args.get("path", "")), str(args.get("content", "")))
    if action == "list_dir":
        return await list_dir_any(str(args.get("path", ".")))
    if action == "search_files":
        return await search_files_any(
            str(args.get("pattern", "")),
            str(args.get("path", ".")),
            bool(args.get("is_regex", False)),
        )
    if action == "delete_path":
        return await delete_path_any(str(args.get("path", "")))
    if action == "python_eval":
        return await python_eval_any(str(args.get("code", "")))
    if action == "gorsel_analiz":
        return await gorsel_analiz_any(
            str(args.get("dosya_yolu", args.get("path", ""))),
            str(args.get("prompt", args.get("istek", ""))),
        )
    if action == "screenshot":
        return await screenshot_any(args if isinstance(args, dict) else {})
    if action == "ocr_screen":
        return await ocr_screen_any(args if isinstance(args, dict) else {})
    if action == "learn_note":
        raw_tags = args.get("tags", [])
        tags = [str(tag) for tag in raw_tags] if isinstance(raw_tags, list) else None
        return await learn_note_any(str(args.get("note", "")), tags)
    if action == "think":
        return AgentResult(ok=True, payload={"note": "think acknowledged"})
    if action == "stop":
        return AgentResult(ok=True, payload={"note": "stop requested"})
    return AgentResult(ok=False, payload={"error": "unknown_action", "action": action})


def _short_json(data: dict[str, Any], limit: int = 900) -> str:
    text = json.dumps(data, ensure_ascii=False, indent=2)
    return _trim_text(text, limit)


def _set_console_quiet_mode(enabled: bool) -> None:
    logger_obj = LOGGER._logger
    target_level = logging.CRITICAL + 1 if enabled else logging.INFO
    for handler in logger_obj.handlers:
        if isinstance(handler, logging.StreamHandler) and not isinstance(handler, logging.FileHandler):
            handler.setLevel(target_level)


def _print_streaming(text: str, delay: float = STREAM_CHAR_DELAY) -> None:
    for ch in text:
        sys.stdout.write(ch)
        sys.stdout.flush()
        if delay > 0:
            time.sleep(delay)
    print()


async def _wait_with_spinner(task: asyncio.Task[str]) -> str:
    spinner = "|/-\\"
    idx = 0
    while not task.done():
        sys.stdout.write(f"\rDervis dusunuyor {spinner[idx % len(spinner)]}")
        sys.stdout.flush()
        idx += 1
        await asyncio.sleep(0.12)
    sys.stdout.write("\r" + " " * 30 + "\r")
    sys.stdout.flush()
    return await task


def _save_memory(session_id: str, conversation: list[dict[str, str]]) -> None:
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    path = MEMORY_DIR / f"{session_id}.json"
    path.write_text(json.dumps(conversation, ensure_ascii=False, indent=2), encoding="utf-8")


def _load_memory(session_id: str) -> list[dict[str, str]]:
    path = MEMORY_DIR / f"{session_id}.json"
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            pass
    return []


def _summarize_old_messages(conversation: list[dict[str, str]], keep_last: int = 20) -> list[dict[str, str]]:
    if len(conversation) <= keep_last + 1:
        return conversation
    system = conversation[0]
    old_part = conversation[1:-keep_last]
    recent_part = conversation[-keep_last:]
    summary_texts = []
    for msg in old_part:
        role = msg["role"]
        text = msg["content"][:120]
        summary_texts.append(f"[{role}] {text}")
    summary_msg = {
        "role": "user",
        "content": f"Onceki konusma ozeti ({len(old_part)} mesaj):\n" + "\n".join(summary_texts[-10:]),
    }
    return [system, summary_msg] + recent_part


async def run_goal(
    goal: str,
    max_steps: int = 20,
    echo: bool = True,
    history: list[dict[str, str]] | None = None,
    learning_context: str = "",
    user_profile: str = "",
) -> str:
    runtime_system_prompt = _compose_runtime_system_prompt()
    task_prompt = {
        "role": "user",
        "content": (
            f"Gorev: {goal}\n"
            "Gorev tamamlandiginda action=think don ve args.answer alanina kullaniciya verilecek net mesaji yaz."
        ),
    }

    if history is not None and len(history) > 1:
        conversation = _summarize_old_messages(history)
        if conversation and conversation[0].get("role") == "system":
            conversation[0]["content"] = runtime_system_prompt
        else:
            conversation.insert(0, {"role": "system", "content": runtime_system_prompt})
    else:
        conversation = [
            {"role": "system", "content": runtime_system_prompt},
        ]

    if user_profile:
        conversation.append({"role": "user", "content": user_profile})
    if learning_context:
        conversation.append(
            {
                "role": "user",
                "content": "Daha once ogrenilen ilgili notlar:\n" + learning_context,
            }
        )
    conversation.append(task_prompt)

    for step in range(1, max_steps + 1):
        response = await asyncio.to_thread(
            llm_chat,
            model=MODEL_NAME,
            messages=conversation,
            options=MODEL_OPTIONS,
        )
        content = response.get("message", {}).get("content", "")
        action_data = _parse_action(content)
        action = str(action_data.get("action", "think"))
        args = action_data.get("args", {})
        if not isinstance(args, dict):
            args = {}

        if echo:
            print(f"\n[Adim {step}] MODEL")
            print(_trim_text(content, 1000))

        if action == "think":
            answer = str(
                args.get("answer")
                or _extract_display_answer(str(action_data.get("raw", "")))
                or "Islem tamamlandi."
            )
            conversation.append({"role": "assistant", "content": content})
            if echo:
                print("\n[CEVAP]")
                print(answer)
            return answer

        if action == "stop":
            return "Model stop aksiyonu verdi."

        result = await _execute_action(action, args)
        if echo:
            print(f"\n[AKSIYON] {action}")
            print(_short_json({"ok": result.ok, "result": result.payload}, 1200))

        feedback = {
            "step": step,
            "action": action,
            "ok": result.ok,
            "result": result.payload,
        }

        conversation.append({"role": "assistant", "content": json.dumps(action_data, ensure_ascii=False)})
        conversation.append(
            {
                "role": "user",
                "content": (
                    "Eylem sonucu JSON:\n"
                    + json.dumps(feedback, ensure_ascii=False)
                    + "\nDevam et. Gorev bittiyse action=think ve args.answer ile don."
                ),
            }
        )

    return "Adim limiti doldu, gorev tamamlanmadi."


async def dervis_core_loop() -> None:
    LOGGER.success("Dervis Core baslatildi", model=MODEL_NAME, root=str(ROOT_DIR))

    conversation: list[dict[str, str]] = [
        {"role": "system", "content": _compose_runtime_system_prompt()},
        {
            "role": "user",
            "content": "Calisma moduna gec. Su an internete erisebilirsin ve terminal komutu verebilirsin. Ilk aksiyonu planla.",
        },
    ]

    while True:
        if conversation and conversation[0].get("role") == "system":
            conversation[0]["content"] = _compose_runtime_system_prompt()
        response = await asyncio.to_thread(
            llm_chat,
            model=MODEL_NAME,
            messages=conversation,
            options=MODEL_OPTIONS,
        )
        content = response.get("message", {}).get("content", "")
        LOGGER.info("Model cevabi alindi", response=_trim_text(content, 600))

        action_data = _parse_action(content)
        action = str(action_data.get("action", "think"))
        args = action_data.get("args", {})
        if not isinstance(args, dict):
            args = {}

        result = await _execute_action(action, args)

        if action == "stop":
            LOGGER.success("Model donguyu sonlandirdi")
            break

        feedback = {
            "action": action,
            "ok": result.ok,
            "result": result.payload,
        }

        conversation.append({"role": "assistant", "content": json.dumps(action_data, ensure_ascii=False)})
        conversation.append(
            {
                "role": "user",
                "content": (
                    "Eylem sonucu JSON:\n"
                    + json.dumps(feedback, ensure_ascii=False)
                    + "\nSonraki adim icin yeni JSON aksiyonu uret."
                ),
            }
        )


async def interactive_chat_loop() -> None:
    _set_console_quiet_mode(True)
    session_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    history = _load_memory("latest")
    profile = _load_learning_profile()
    if not history:
        history = [{"role": "system", "content": SYSTEM_PROMPT}]
    print(f"Dervis Core Chat | Model: {MODEL_NAME} | ctx: {NUM_CTX}")
    print("Komutlar: cikis, /temizle, /hafiza, /verbose, /ogren <not>, /geri <1-5> <yorum>, /profil")
    verbose = False

    while True:
        user_text = await asyncio.to_thread(input, "\nSen> ")
        stripped = user_text.strip()
        if stripped.lower() in {"cikis", "exit", "quit"}:
            _save_memory("latest", history)
            _save_memory(session_id, history)
            _save_learning_profile(profile)
            print("Hafiza kaydedildi. Gorusmek uzere.")
            break
        if not stripped:
            continue
        if stripped == "/temizle":
            history = [{"role": "system", "content": SYSTEM_PROMPT}]
            print("Sohbet hafizasi temizlendi.")
            continue
        if stripped == "/hafiza":
            learning_count = len(_read_jsonl(LEARNING_DB_PATH, limit=5000))
            print(f"Sohbet mesaji: {len(history)} | Ogrenme notu: {learning_count} | Session: {session_id}")
            continue
        if stripped == "/profil":
            print(_profile_prompt(profile))
            continue
        if stripped == "/verbose":
            verbose = not verbose
            print(f"Detayli mod: {'ACIK' if verbose else 'KAPALI'}")
            continue
        if stripped.startswith("/ogren "):
            note = stripped[7:].strip()
            if note:
                _record_learning(kind="manual_note", content=note, source="user_command")
                print("Ogrenme notu kaydedildi.")
            else:
                print("Kullanim: /ogren <not>")
            continue
        if stripped.startswith("/geri"):
            parts = stripped.split(maxsplit=2)
            if len(parts) < 2 or not parts[1].isdigit():
                print("Kullanim: /geri <1-5> <yorum>")
                continue
            rating = int(parts[1])
            comment = parts[2] if len(parts) > 2 else ""
            profile = _update_profile_feedback(profile, rating, comment)
            _save_learning_profile(profile)
            _record_learning(
                kind="feedback",
                content=f"Puan: {rating} | Yorum: {comment or '<bos>'}",
                source="user_feedback",
                tags=["feedback", "rating", str(rating)],
            )
            print(f"Geri bildirim kaydedildi. Ortalama puan: {profile.get('avg_rating')}")
            continue
        normalized = stripped.lower()
        if "hangi dil modeli" in normalized or "hangi modelsin" in normalized or "modelin ne" in normalized:
            _print_streaming("qwen2.5-coder:14b (Ollama, lokal, Apple M5 Pro)")
            continue

        if _is_ocr_request(stripped):
            ocr_result = await ocr_screen_any({})
            if ocr_result.ok:
                ocr_text = ocr_result.payload.get("text", "")
                msg = ocr_result.payload.get("message", "")
                answer = f"{msg}\n\n--- EKRANDAN OKUNAN METİN ---\n{ocr_text}" if ocr_text else msg
            else:
                answer = "OCR basarisiz: " + str(ocr_result.payload.get("detail") or ocr_result.payload.get("error"))
            history.append({"role": "user", "content": stripped})
            history.append({"role": "assistant", "content": answer})
            _print_streaming(answer)
            continue

        if _is_visual_request(stripped):
            image_path = _extract_image_path_from_text(stripped)
            # Kullanici belirli bir dosya vermediyse taze ekran goruntusu al
            if not image_path:
                shot = await screenshot_any({})
                if shot.ok:
                    image_path = shot.payload.get("path", "")
            visual_result = await gorsel_analiz_any(image_path, user_query=stripped)
            if visual_result.ok:
                used_path = str(visual_result.payload.get("dosya_yolu", ""))
                analysis_text = str(visual_result.payload.get("analiz", ""))
                answer = (
                    (f"Analiz edilen dosya: {used_path}\n\n" if used_path else "")
                    + (analysis_text or "Gorsel analiz tamamlandi ancak metin donmedi.")
                )
            else:
                answer = (
                    "Gorsel analizi yapamadim: "
                    + str(visual_result.payload.get("detail") or visual_result.payload.get("error") or "bilinmeyen hata")
                )

            history.append({"role": "user", "content": stripped})
            history.append({"role": "assistant", "content": answer})
            _record_learning(
                kind="dialog_pair",
                content=f"Soru: {stripped}\nCevap: {answer}",
                source="interactive_chat_visual",
            )
            _print_streaming(answer)
            continue

        learning_context = _get_learning_context(stripped)
        profile_context = _profile_prompt(profile)
        history.append({"role": "user", "content": stripped})
        answer_task = asyncio.create_task(
            run_goal(
                stripped,
                max_steps=20,
                echo=verbose,
                history=history,
                learning_context=learning_context,
                user_profile=profile_context,
            )
        )
        answer = await _wait_with_spinner(answer_task)
        history.append({"role": "assistant", "content": answer})
        _record_learning(
            kind="dialog_pair",
            content=f"Soru: {stripped}\nCevap: {answer}",
            source="interactive_chat",
        )
        _print_streaming(answer)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Dervis Core ajan calistirici")
    parser.add_argument(
        "--chat",
        action="store_true",
        help="Terminalde etkilesimli sohbet modu baslatir.",
    )
    return parser


def cleanup_old_backups(max_age_days: int = 30, dry_run: bool = False) -> dict[str, Any]:
    """projects/ altındaki .bak dosyalarını temizler (30 günden eski).

    Args:
        max_age_days: Kaç günden eski dosyalar silinsin (varsayılan: 30)
        dry_run: True ise silmez, sadece sayar
    Returns:
        {"deleted": int, "skipped": int, "total_size_kb": float, "paths": list}
    """
    import time as _time

    cutoff = _time.time() - (max_age_days * 86400)
    projects_dir = ROOT_DIR / "projects"
    deleted = 0
    skipped = 0
    total_size_kb = 0.0
    removed_paths: list[str] = []

    if not projects_dir.exists():
        return {"deleted": 0, "skipped": 0, "total_size_kb": 0.0, "paths": []}

    for bak in projects_dir.rglob("*.bak"):
        try:
            mtime = bak.stat().st_mtime
            size_kb = bak.stat().st_size / 1024
            if mtime < cutoff:
                total_size_kb += size_kb
                if dry_run:
                    skipped += 1
                    removed_paths.append(str(bak))
                else:
                    bak.unlink()
                    deleted += 1
                    removed_paths.append(str(bak))
            else:
                skipped += 1
        except Exception:
            skipped += 1

    return {
        "deleted": deleted,
        "skipped": skipped,
        "total_size_kb": round(total_size_kb, 2),
        "paths": removed_paths[:100],  # sadece ilk 100ünü döndür
        "dry_run": dry_run,
    }


if __name__ == "__main__":
    args = _build_parser().parse_args()
    if args.chat:
        asyncio.run(interactive_chat_loop())
    else:
        asyncio.run(dervis_core_loop())
