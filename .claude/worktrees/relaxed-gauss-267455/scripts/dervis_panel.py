from __future__ import annotations

import os
import sys
import asyncio

# Prevent local scripts (e.g., scripts/operator.py) from shadowing stdlib modules.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR in sys.path:
    sys.path.remove(SCRIPT_DIR)

import json
import importlib
import queue
import subprocess
import threading
import textwrap
import importlib
import traceback
import tkinter as tk
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from tkinter import filedialog
from typing import Any, Optional

import requests

# Import local bridge safely without permanently prioritizing scripts/ on sys.path.
if SCRIPT_DIR not in sys.path:
    sys.path.append(SCRIPT_DIR)
from llm_bridge import ensure_local_ollama_running, get_default_model_name, get_identity_label, stream_chat
if SCRIPT_DIR in sys.path:
    sys.path.remove(SCRIPT_DIR)

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD

    HAS_DND = True
except Exception:
    HAS_DND = False
    DND_FILES = "DND_Files"
    TkinterDnD = None

MODEL_NAME = get_default_model_name()
ROOT_DIR = Path(__file__).resolve().parents[1]
PANEL_MEMORY_PATH     = ROOT_DIR / "data" / "chat_memory" / "panel_latest.json"
LEARNING_MEMORY_PATH  = ROOT_DIR / "data" / "learning_memory.jsonl"
LEARNING_PROFILE_PATH = ROOT_DIR / "data" / "learning_profile.json"
NIYET_DEFTERI_PATH    = ROOT_DIR / "data" / "niyet_defteri.txt"


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except Exception:
        return default


def _env_bool(name: str, default: bool = False) -> bool:
    raw = str(os.getenv(name, "")).strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "on", "fast", "hizli"}


PANEL_FAST_MODE_DEFAULT = _env_bool("DERGAH_PANEL_FAST_MODE", False)
STREAM_TIMEOUT_NORMAL = _env_int("DERGAH_PANEL_STREAM_TIMEOUT", 90)
STREAM_TIMEOUT_FAST = _env_int("DERGAH_PANEL_STREAM_TIMEOUT_FAST", 30)
AGENT_MAX_STEPS_NORMAL = _env_int("DERGAH_PANEL_AGENT_MAX_STEPS", 8)
AGENT_MAX_STEPS_FAST = _env_int("DERGAH_PANEL_AGENT_MAX_STEPS_FAST", 3)

WINDOW_WIDTH  = 460
WINDOW_HEIGHT = 820
MAX_FILE_CHARS = 6000

MODEL_OPTIONS = {
    "num_ctx": 16384,
    "temperature": 0.4,
    "top_p": 0.9,
    "repeat_penalty": 1.1,
}

USER_BUBBLE_MAX_CHARS = 26
AI_BUBBLE_MAX_CHARS = 30
_DERVIS_CORE_MODULE: Any | None = None
_OTONOM_PROJE_MODULE: Any | None = None

_SYSTEM_BASE = (
    f"Sen Dervis Core adli yerel asistansin. Kimligin: {get_identity_label(MODEL_NAME)}.\n"
    "Turkce, net ve uygulamaya donuk cevaplar ver. Asla JSON semasi yazma, sadece dogal metinle cevap ver.\n"
    "Asla GPT, OpenAI veya baska bir bulut modeli kimligini iddia etme.\n"
    "ONEMLI: Asla 'surekli ogrenme yetenegim yok' veya 'gecmisi hatirlayamam' deme.\n"
    "Asagida [Ne Ogrendim] ve [Kullanici Profili] basliklari altinda GERCEK hafiza verilerin var.\n"
    "Bu veriler sana sorulursa dogrudan oku ve paylas."
)


def _build_system_prompt() -> str:
    """Her sohbet oncesinde ogrenim verilerini okuyarak dinamik sistem promptu olusturur."""
    sections: list[str] = [_SYSTEM_BASE]

    # 1. Kullanici profili (stil tercihi, geri bildirim ozeti)
    try:
        if LEARNING_PROFILE_PATH.exists():
            profile = json.loads(LEARNING_PROFILE_PATH.read_text(encoding="utf-8"))
            style   = profile.get("preferred_style", "")
            rating  = profile.get("avg_rating", "")
            last_fb = profile.get("last_feedback", "")
            parts: list[str] = []
            if style:
                parts.append(f"Tercih edilen cevap stili: {style}")
            if rating:
                parts.append(f"Ortalama memnuniyet puani: {rating}/5")
            if last_fb:
                parts.append(f"Son geri bildirim: {last_fb}")
            if parts:
                sections.append("\n[Kullanici Profili]\n" + "\n".join(parts))
    except Exception:
        pass

    # 2. Son ogrenme notlari (en fazla 12 girdi)
    try:
        if LEARNING_MEMORY_PATH.exists():
            lines = LEARNING_MEMORY_PATH.read_text(encoding="utf-8", errors="ignore").splitlines()
            notes: list[str] = []
            for raw in reversed(lines):
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    entry = json.loads(raw)
                    kind    = entry.get("kind", "")
                    content = str(entry.get("content", "")).strip()
                    if kind in {"manual_note", "feedback"} and content:
                        notes.append(f"• {content}")
                        if len(notes) >= 12:
                            break
                except Exception:
                    continue
            if notes:
                sections.append("\n[Ne Ogrendim]\n" + "\n".join(reversed(notes)))
    except Exception:
        pass

    # 3. Niyet defteri (son 10 satir)
    try:
        if NIYET_DEFTERI_PATH.exists():
            niyet_lines = NIYET_DEFTERI_PATH.read_text(encoding="utf-8", errors="ignore").splitlines()
            tail = [l for l in niyet_lines if l.strip()][-10:]
            if tail:
                sections.append("\n[Kullanici Niyet/Hedef Gecmisi]\n" + "\n".join(tail))
    except Exception:
        pass

    return "\n".join(sections)


def _load_dervis_core_module() -> Any:
    global _DERVIS_CORE_MODULE
    if _DERVIS_CORE_MODULE is not None:
        return _DERVIS_CORE_MODULE

    script_dir_str = str(SCRIPT_DIR)
    if script_dir_str not in sys.path:
        sys.path.append(script_dir_str)

    _DERVIS_CORE_MODULE = importlib.import_module("dervis_core")
    return _DERVIS_CORE_MODULE


def _load_otonom_proje_module() -> Any:
    global _OTONOM_PROJE_MODULE
    if _OTONOM_PROJE_MODULE is not None:
        return _OTONOM_PROJE_MODULE

    script_dir_str = str(SCRIPT_DIR)
    if script_dir_str not in sys.path:
        sys.path.append(script_dir_str)

    _OTONOM_PROJE_MODULE = importlib.import_module("emare_otonom_proje")
    return _OTONOM_PROJE_MODULE


def _load_learning_context_text(limit: int = 6) -> str:
    items: list[str] = []
    try:
        if LEARNING_MEMORY_PATH.exists():
            lines = LEARNING_MEMORY_PATH.read_text(encoding="utf-8", errors="ignore").splitlines()
            for raw in reversed(lines):
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    entry = json.loads(raw)
                except Exception:
                    continue
                kind = str(entry.get("kind", "")).strip()
                content = str(entry.get("content", "")).strip()
                if kind not in {"manual_note", "feedback"}:
                    continue
                if content:
                    items.append(content[:300])
                if len(items) >= limit:
                    break
    except Exception:
        return ""
    return "\n".join(reversed(items))


def _load_user_profile_text() -> str:
    try:
        if not LEARNING_PROFILE_PATH.exists():
            return ""
        profile = json.loads(LEARNING_PROFILE_PATH.read_text(encoding="utf-8"))
    except Exception:
        return ""

    lines: list[str] = []
    style = str(profile.get("preferred_style", "")).strip()
    rating = str(profile.get("avg_rating", "")).strip()
    feedback = str(profile.get("last_feedback", "")).strip()
    if style:
        lines.append(f"Tercih edilen cevap stili: {style}")
    if rating:
        lines.append(f"Ortalama memnuniyet puani: {rating}/5")
    if feedback:
        lines.append(f"Son geri bildirim: {feedback}")
    return "\n".join(lines)


def _normalize_query(text: str) -> str:
    table = str.maketrans({
        "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u",
        "Ç": "c", "Ğ": "g", "İ": "i", "I": "i", "Ö": "o", "Ş": "s", "Ü": "u",
    })
    return text.translate(table).lower().strip()


def _is_autonomous_project_start(text: str) -> bool:
    normalized = _normalize_query(text)
    triggers = [
        "yazmaya basla",
        "yazmaya başla",
        "/yazmaya-basla",
        "/otonom-proje",
        "projeyi yazmaya basla",
        "projeyi yazmaya başla",
    ]
    return any(trigger in normalized for trigger in triggers)


def _is_memory_question(text: str) -> bool:
    normalized = _normalize_query(text)
    prompts = [
        "ne ogrendin",
        "neler ogrendin",
        "bugun ne ogrendin",
        "bugun neler ogrendin",
        "benden ne ogrendin",
        "benim hakkimda ne biliyorsun",
        "beni ne kadar taniyorsun",
        "neler biliyorsun",
        "hatirliyor musun",
    ]
    return any(prompt in normalized for prompt in prompts)


def _strip_timestamp_prefix(line: str) -> str:
    if line.startswith("[") and "]" in line:
        return line.split("]", 1)[1].strip()
    return line.strip()


def _compose_memory_reply() -> str:
    learned: list[str] = []
    style = ""
    last_feedback = ""

    try:
        if LEARNING_PROFILE_PATH.exists():
            profile = json.loads(LEARNING_PROFILE_PATH.read_text(encoding="utf-8"))
            style = str(profile.get("preferred_style", "")).strip()
            last_feedback = str(profile.get("last_feedback", "")).strip()
    except Exception:
        pass

    try:
        if LEARNING_MEMORY_PATH.exists():
            lines = LEARNING_MEMORY_PATH.read_text(encoding="utf-8", errors="ignore").splitlines()
            for raw in reversed(lines):
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    entry = json.loads(raw)
                except Exception:
                    continue
                kind = str(entry.get("kind", "")).strip()
                content = str(entry.get("content", "")).strip()
                if kind == "manual_note" and content:
                    learned.append(content)
                if len(learned) >= 4:
                    break
    except Exception:
        pass

    goals: list[str] = []
    try:
        if NIYET_DEFTERI_PATH.exists():
            lines = NIYET_DEFTERI_PATH.read_text(encoding="utf-8", errors="ignore").splitlines()
            goals = [_strip_timestamp_prefix(line) for line in lines if line.strip()][-3:]
    except Exception:
        pass

    parts: list[str] = []
    if learned:
        parts.append("Şunları öğrendim:")
        parts.extend(f"- {item}" for item in reversed(learned))
    if goals:
        parts.append("Şu anki odağın ise şöyle görünüyor:")
        parts.extend(f"- {item}" for item in goals)
    if style:
        parts.append(f"Cevap tarzı tercihin: {style}.")
    if last_feedback:
        parts.append(f"Son geri bildirimin: {last_feedback}.")

    if not parts:
        return "Henüz kayda geçmiş bir öğrenme notum yok."
    return "\n".join(parts)


def _measure_bubble(text: str, max_chars: int) -> tuple[int, int]:
    content = text or " "
    wrapped: list[str] = []
    for raw_line in content.splitlines() or [""]:
        pieces = textwrap.wrap(
            raw_line or " ",
            width=max_chars,
            break_long_words=True,
            replace_whitespace=False,
            drop_whitespace=False,
        )
        wrapped.extend(pieces or [" "])
    width = max(6, min(max_chars, max(len(piece.rstrip()) or 1 for piece in wrapped)))
    height = max(1, len(wrapped))
    return width + 1, height

# ── Palet ──────────────────────────────────────────────────────────────────
C_BG          = "#e7ddd4"
C_HEADER      = "#075e54"
C_HEADER_LINE = "#0b7a6d"
C_BUBBLE_USER = "#dcf8c6"
C_BUBBLE_AI   = "#ffffff"
C_TXT_USER    = "#0f5132"
C_TXT_AI      = "#1f2937"
C_TXT_SEC     = "#667781"
C_INPUT_BG    = "#ffffff"
C_INPUT_BDR   = "#d1d7db"
C_SEND        = "#00a884"
C_SEND_HOV    = "#008069"
C_DIVIDER     = "#d8d4cf"
C_THINK_BG    = "#ffffff"
C_STATUS_OK   = "#25d366"

# ── Font ────────────────────────────────────────────────────────────────────
F_TITLE   = ("Helvetica Neue", 16, "bold")
F_SUB     = ("Helvetica Neue", 10)
F_BUBBLE  = ("Helvetica Neue", 13)
F_STAMP   = ("Helvetica Neue", 9)
F_INPUT   = ("Helvetica Neue", 13)
F_BTN     = ("Helvetica Neue", 18, "bold")


@dataclass
class BubbleRef:
    content_label: tk.Text
    frame: tk.Frame


def _now_hm() -> str:
    return datetime.now().strftime("%H:%M")


def _parse_drop_paths(raw: str) -> list[str]:
    # macOS/tk usually sends "{path with spaces} {/another/path}" style payload.
    result: list[str] = []
    token = ""
    in_brace = False
    for ch in raw:
        if ch == "{" and not in_brace:
            in_brace = True
            token = ""
            continue
        if ch == "}" and in_brace:
            in_brace = False
            if token:
                result.append(token)
            token = ""
            continue
        if in_brace:
            token += ch
            continue
        if ch.isspace():
            if token:
                result.append(token)
                token = ""
        else:
            token += ch
    if token:
        result.append(token)
    return [p for p in result if p.strip()]


def _read_file_preview(path: Path, max_chars: int = MAX_FILE_CHARS) -> str:
    text = path.read_text(encoding="utf-8", errors="ignore")
    if len(text) <= max_chars:
        return text
    return text[:max_chars] + "\n...<kisaltilmis_dosya_icerigi>"


class DervisPanel:
    def __init__(self) -> None:
        self.root = TkinterDnD.Tk() if HAS_DND and TkinterDnD else tk.Tk()
        self.root.title("Dervis")
        self.root.configure(bg=C_HEADER)
        self.root.resizable(False, False)
        self.root.overrideredirect(True)
        self.root.after(0, self._enforce_window_style)

        self.messages: list[dict[str, str]] = []
        self.busy = False
        self._stop_event = threading.Event()
        self.pending_user_text: str = ""
        self.current_ai_text = ""
        self.current_assistant_ref: Optional[BubbleRef] = None
        self.event_queue: queue.Queue[tuple[str, Any]] = queue.Queue()
        self._drag_start: Optional[tuple[int, int, int, int]] = None
        self.placeholder_text = "Bir mesaj yaz..."
        self.placeholder_active = False
        self.fast_mode = PANEL_FAST_MODE_DEFAULT
        self._fast_btn: Optional[tk.Button] = None

        self.status_text = tk.StringVar(value=self._idle_status_text())

        self._place_bottom_right()
        self._build_ui()
        self._load_memory()
        self._render_history()
        if not self.messages:
            self._append_message("assistant", "Merhaba! Ben Derviş. Sana nasıl yardımcı olabilirim?")

        self.root.after(50, self._poll_events)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        # Koordinatör arka plan thread'i — dervişlerin sorularını otomatik yanıtlar
        self._koordinator_stop = threading.Event()
        self._koordinator_thread = threading.Thread(
            target=self._run_koordinator, daemon=True
        )
        self._koordinator_thread.start()

    def _run_koordinator(self) -> None:
        try:
            if SCRIPT_DIR not in sys.path:
                sys.path.append(SCRIPT_DIR)
            import dervis_koordinator as dk
            dk.run_loop(
                "yonetici",
                interval_sec=15,
                limit=40,
                stop_event=self._koordinator_stop,
            )
        except Exception:
            pass  # panel kapatılınca sessizce dur

    def _idle_status_text(self) -> str:
        return "Hazır • Hızlı" if self.fast_mode else "Hazır"

    def _set_fast_mode(self, enabled: bool) -> None:
        self.fast_mode = enabled
        self._refresh_fast_button()
        if not self.busy:
            self.status_text.set(self._idle_status_text())

    def _toggle_fast_mode(self) -> None:
        self._set_fast_mode(not self.fast_mode)

    def _refresh_fast_button(self) -> None:
        if self._fast_btn is None:
            return
        if self.fast_mode:
            self._fast_btn.configure(
                text="⚡",
                bg="#0f172a",
                fg="#facc15",
                activebackground="#1e293b",
                activeforeground="#fde68a",
            )
            return
        self._fast_btn.configure(
            text="○",
            bg=C_HEADER,
            fg="#64748b",
            activebackground="#334155",
            activeforeground="#f8fafc",
        )

    def _enforce_window_style(self) -> None:
        # macOS bazen ilk frame'de native title bar gosteriyor; bunu tekrar zorla.
        self.root.overrideredirect(True)

    def _place_bottom_right(self) -> None:
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        panel_h = min(WINDOW_HEIGHT, max(600, screen_h - 100))
        x = max(16, screen_w - WINDOW_WIDTH - 20)
        y = max(16, screen_h - panel_h - 36)
        self.root.geometry(f"{WINDOW_WIDTH}x{panel_h}+{x}+{y}")

    def _start_move(self, event: tk.Event) -> None:
        self._drag_start = (event.x_root, event.y_root, self.root.winfo_x(), self.root.winfo_y())

    def _on_move(self, event: tk.Event) -> None:
        if not self._drag_start:
            return
        sxr, syr, sx, sy = self._drag_start
        self.root.geometry(f"+{sx + event.x_root - sxr}+{sy + event.y_root - syr}")

    def _end_move(self, _event: tk.Event) -> None:
        self._drag_start = None

    def _build_ui(self) -> None:
        # En dıştaki ince gölge çerçevesi
        shadow = tk.Frame(self.root, bg="#1e293b", padx=1, pady=1)
        shadow.pack(fill=tk.BOTH, expand=True)

        container = tk.Frame(shadow, bg=C_BG)
        container.pack(fill=tk.BOTH, expand=True)

        self._build_header(container)
        self._build_chat_area(container)
        self._build_composer(container)

    def _build_header(self, parent: tk.Frame) -> None:
        header = tk.Frame(parent, bg=C_HEADER, height=68)
        header.pack(fill=tk.X)
        header.pack_propagate(False)

        # Avatar dairesi
        av = tk.Canvas(header, width=38, height=38, bg=C_HEADER, highlightthickness=0)
        av.pack(side=tk.LEFT, padx=(14, 10), pady=15)
        av.create_oval(2, 2, 36, 36, fill="#2563eb", outline="#3b82f6", width=2)
        av.create_text(19, 19, text="D", fill="white", font=("Helvetica Neue", 14, "bold"))

        # Başlık
        title_col = tk.Frame(header, bg=C_HEADER)
        title_col.pack(side=tk.LEFT, fill=tk.Y, pady=12)

        tk.Label(title_col, text="Derviş", bg=C_HEADER, fg="#f8fafc", font=F_TITLE, anchor="w").pack(anchor="w")

        sub_row = tk.Frame(title_col, bg=C_HEADER)
        sub_row.pack(anchor="w", pady=(1, 0))

        dot = tk.Canvas(sub_row, width=7, height=7, bg=C_HEADER, highlightthickness=0)
        dot.pack(side=tk.LEFT, padx=(0, 4))
        dot.create_oval(1, 1, 6, 6, fill=C_STATUS_OK, outline="")

        self._status_lbl = tk.Label(
            sub_row, textvariable=self.status_text,
            bg=C_HEADER, fg="#94a3b8", font=F_SUB
        )
        self._status_lbl.pack(side=tk.LEFT)

        # Sağ butonlar
        right = tk.Frame(header, bg=C_HEADER)
        right.pack(side=tk.RIGHT, padx=10)

        self._close_btn = tk.Button(
            right, text="✕", command=self._on_close,
            bg=C_HEADER, fg="#64748b",
            activebackground="#334155", activeforeground="#f8fafc",
            borderwidth=0, highlightthickness=0,
            font=("Helvetica Neue", 13), cursor="hand2",
        )
        self._close_btn.pack(side=tk.RIGHT)

        clear_btn = tk.Button(
            right, text="⌫", command=self._clear_chat,
            bg=C_HEADER, fg="#64748b",
            activebackground="#334155", activeforeground="#f8fafc",
            borderwidth=0, highlightthickness=0,
            font=("Helvetica Neue", 13), cursor="hand2",
        )
        clear_btn.pack(side=tk.RIGHT, padx=(0, 10))

        self._fast_btn = tk.Button(
            right,
            text="○",
            command=self._toggle_fast_mode,
            bg=C_HEADER,
            fg="#64748b",
            activebackground="#334155",
            activeforeground="#f8fafc",
            borderwidth=0,
            highlightthickness=0,
            font=("Helvetica Neue", 13, "bold"),
            cursor="hand2",
            width=2,
        )
        self._fast_btn.pack(side=tk.RIGHT, padx=(0, 8))
        self._refresh_fast_button()

        # Sürükleme
        for w in [header, title_col, av, sub_row]:
            w.bind("<ButtonPress-1>", self._start_move)
            w.bind("<B1-Motion>", self._on_move)
            w.bind("<ButtonRelease-1>", self._end_move)

        # Alt ayırıcı çizgi
        tk.Frame(parent, bg=C_HEADER_LINE, height=1).pack(fill=tk.X)

    def _build_chat_area(self, parent: tk.Frame) -> None:
        chat_wrap = tk.Frame(parent, bg=C_BG)
        chat_wrap.pack(fill=tk.BOTH, expand=True)

        self.chat_canvas = tk.Canvas(chat_wrap, bg=C_BG, highlightthickness=0, borderwidth=0)
        self.chat_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.chat_scrollbar = tk.Scrollbar(
            chat_wrap,
            orient=tk.VERTICAL,
            command=self.chat_canvas.yview,
            width=10,
            bd=0,
            highlightthickness=0,
            troughcolor="#d9dbd7",
            bg="#b7c4bc",
            activebackground="#91a89b",
        )
        self.chat_scrollbar.pack(side=tk.RIGHT, fill=tk.Y, padx=(0, 4), pady=6)
        self.chat_canvas.configure(yscrollcommand=self.chat_scrollbar.set)

        self.messages_frame = tk.Frame(self.chat_canvas, bg=C_BG)
        self.messages_window = self.chat_canvas.create_window((0, 0), window=self.messages_frame, anchor="nw")

        self.messages_frame.bind(
            "<Configure>",
            lambda _e: self.chat_canvas.configure(scrollregion=self.chat_canvas.bbox("all")),
        )
        self.chat_canvas.bind("<Configure>", self._on_canvas_resize)
        self._bind_scroll_proxy(self.chat_canvas)
        self._bind_scroll_proxy(self.messages_frame)
        self._paint_chat_wallpaper()

    def _build_composer(self, parent: tk.Frame) -> None:
        tk.Frame(parent, bg=C_DIVIDER, height=1).pack(fill=tk.X)

        outer = tk.Frame(parent, bg="#f0f2f5", padx=10, pady=8)
        outer.pack(fill=tk.X)

        # Input kutusu
        bdr = tk.Frame(outer, bg=C_INPUT_BDR, padx=1, pady=1)
        bdr.pack(side=tk.LEFT, fill=tk.X, expand=True)

        inner = tk.Frame(bdr, bg=C_INPUT_BG)
        inner.pack(fill=tk.BOTH)

        self.input_var = tk.StringVar()
        self.input_entry = tk.Entry(
            inner, textvariable=self.input_var,
            font=F_INPUT, bg=C_INPUT_BG, fg="#1e293b",
            relief=tk.FLAT, highlightthickness=0,
            insertbackground=C_SEND,
        )
        self.input_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(10, 6), pady=9, ipady=5)
        self.input_entry.bind("<Return>", self._on_send)
        self.input_entry.bind("<FocusIn>", self._on_input_focus_in)
        self.input_entry.bind("<FocusOut>", self._on_input_focus_out)
        self.input_entry.bind("<KeyPress>", self._on_key_press)

        if HAS_DND:
            try:
                self.input_entry.drop_target_register(DND_FILES)
                self.input_entry.dnd_bind("<<Drop>>", self._on_drop)
            except Exception:
                pass

        # Dosya butonu
        self.file_btn = tk.Button(
            outer, text="📎",
            command=self._select_file,
            bg="#f0f2f5", fg="#54656f",
            activebackground="#e2e8f0", activeforeground="#1e293b",
            borderwidth=0, highlightthickness=0,
            font=("Helvetica Neue", 18), cursor="hand2",
        )
        self.file_btn.pack(side=tk.LEFT, padx=(8, 4))

        # Gönder butonu
        self.send_btn = tk.Button(
            outer, text="↑",
            command=self._on_send,
            bg=C_SEND, fg="white",
            activebackground=C_SEND_HOV, activeforeground="white",
            borderwidth=0, highlightthickness=0,
            font=F_BTN, width=2,
            cursor="hand2",
        )
        self.send_btn.pack(side=tk.LEFT, padx=(2, 0), ipady=2)

        # İptal butonu (sadece meşgulken görünür)
        self.stop_btn = tk.Button(
            outer, text="■",
            command=self._on_stop,
            bg="#ef4444", fg="white",
            activebackground="#dc2626", activeforeground="white",
            borderwidth=0, highlightthickness=0,
            font=("Helvetica Neue", 14, "bold"), width=2,
            cursor="hand2",
        )
        # Başlangıçta gizli; _set_busy(True) gösterir

        self._apply_placeholder()
        self.input_entry.focus_set()

    def _add_thinking_bubble(self) -> BubbleRef:
        """Yapay zeka yanıt gönderirken animasyonlu bekleyiş balonu."""
        outer = tk.Frame(self.messages_frame, bg=C_BG)
        outer.pack(fill=tk.X, padx=12, pady=(6, 2))

        row = tk.Frame(outer, bg=C_BG)
        row.pack(side=tk.LEFT, anchor="w")

        av = tk.Canvas(row, width=26, height=26, bg=C_BG, highlightthickness=0)
        av.pack(side=tk.LEFT, anchor="n", padx=(0, 6), pady=(3, 0))
        av.create_oval(2, 2, 24, 24, fill="#2563eb", outline="")
        av.create_text(13, 13, text="D", fill="white", font=("Helvetica Neue", 9, "bold"))

        bubble = tk.Frame(row, bg=C_THINK_BG, highlightthickness=1, highlightbackground=C_DIVIDER)
        bubble.pack(side=tk.LEFT, anchor="w")

        lbl = tk.Text(
            bubble,
            bg=C_THINK_BG,
            fg="#93c5fd",
            font=("Helvetica Neue", 14),
            relief=tk.FLAT,
            bd=0,
            wrap=tk.WORD,
            width=max(24, int((WINDOW_WIDTH - 80) / 8)),
            height=1,
            padx=16,
            pady=10,
            cursor="arrow",
            exportselection=False,
            highlightthickness=0,
        )
        lbl.insert("1.0", "●  ●  ●")
        lbl.configure(state=tk.DISABLED)
        lbl.pack(fill=tk.X, expand=True)
        for widget in (outer, row, bubble, lbl):
            self._bind_scroll_proxy(widget)
        self._scroll_to_bottom()
        return BubbleRef(content_label=lbl, frame=bubble)

    def _apply_placeholder(self) -> None:
        if self.input_var.get().strip():
            return
        self.placeholder_active = True
        self.input_entry.configure(fg="#94a3b8")
        self.input_var.set(self.placeholder_text)

    def _clear_placeholder(self) -> None:
        if not self.placeholder_active:
            return
        self.placeholder_active = False
        self.input_entry.configure(fg="#1e293b")
        self.input_var.set("")

    def _on_key_press(self, event: Any) -> None:
        """Placeholder aktifken herhangi bir tuşa basılırsa temizle."""
        if self.placeholder_active and getattr(event, 'char', '') and event.char.isprintable():
            self._clear_placeholder()

    def _on_input_focus_in(self, _event: Any) -> None:
        self._clear_placeholder()

    def _on_input_focus_out(self, _event: Any) -> None:
        if not self.input_var.get().strip():
            self._apply_placeholder()

    def _on_canvas_resize(self, event: tk.Event) -> None:
        self.chat_canvas.itemconfig(self.messages_window, width=event.width)
        self._paint_chat_wallpaper(event.width, event.height)

    def _on_mouse_wheel(self, event: tk.Event) -> None:
        if sys.platform == "darwin":
            steps = -1 if event.delta > 0 else 1
        else:
            steps = int(-1 * (event.delta / 120))
            if steps == 0 and getattr(event, "delta", 0):
                steps = -1 if event.delta > 0 else 1
        self.chat_canvas.yview_scroll(steps, "units")
        return "break"

    def _bind_scroll_proxy(self, widget: tk.Misc) -> None:
        widget.bind("<MouseWheel>", self._on_mouse_wheel, add="+")

    def _paint_chat_wallpaper(self, width: Optional[int] = None, height: Optional[int] = None) -> None:
        width = width or max(1, self.chat_canvas.winfo_width())
        height = height or max(1, self.chat_canvas.winfo_height())
        self.chat_canvas.delete("wallpaper")

        accents = [
            ("#d7dbd4", 28, 118),
            ("#efede8", 18, 92),
            ("#dde4dd", 14, 136),
        ]
        for row_index, (color, size, step) in enumerate(accents):
            x = -20 + (row_index * 18)
            while x < width + step:
                y = (row_index * 24) + ((x // max(1, step)) % 2) * 26
                while y < height + step:
                    self.chat_canvas.create_oval(
                        x,
                        y,
                        x + size,
                        y + size,
                        fill=color,
                        outline="",
                        tags="wallpaper",
                    )
                    y += step
                x += step

        self.chat_canvas.tag_lower("wallpaper")
        self.chat_canvas.tag_raise(self.messages_window)

    def _scroll_to_bottom(self) -> None:
        self.root.update_idletasks()
        self.chat_canvas.yview_moveto(1.0)

    def _set_text_widget_content(self, widget: tk.Text, text: str, *, bg: str, fg: str) -> None:
        width, height = _measure_bubble(text, AI_BUBBLE_MAX_CHARS)
        widget.configure(state=tk.NORMAL, bg=bg, fg=fg, font=F_BUBBLE)
        widget.delete("1.0", tk.END)
        widget.insert("1.0", text or " ")
        widget.configure(width=width, height=height, state=tk.DISABLED)

    def _add_bubble(self, role: str, content: str, ts: str) -> BubbleRef:
        is_user = role == "user"

        outer = tk.Frame(self.messages_frame, bg=C_BG)
        outer.pack(fill=tk.X, padx=12, pady=(4, 2))

        if is_user:
            bubble = tk.Frame(outer, bg=C_BUBBLE_USER, highlightthickness=0, bd=0)
            bubble.pack(side=tk.RIGHT, anchor="e")
            fg_txt  = C_TXT_USER
            ts_fg   = "#6b8b74"
            max_chars = USER_BUBBLE_MAX_CHARS
        else:
            row = tk.Frame(outer, bg=C_BG)
            row.pack(side=tk.LEFT, anchor="w")

            av = tk.Canvas(row, width=26, height=26, bg=C_BG, highlightthickness=0)
            av.pack(side=tk.LEFT, anchor="n", padx=(0, 6), pady=(3, 0))
            av.create_oval(2, 2, 24, 24, fill="#2563eb", outline="")
            av.create_text(13, 13, text="D", fill="white", font=("Helvetica Neue", 9, "bold"))

            bubble = tk.Frame(row, bg=C_BUBBLE_AI, highlightthickness=0, bd=0)
            bubble.pack(side=tk.LEFT, anchor="w")
            fg_txt  = C_TXT_AI
            ts_fg   = C_TXT_SEC
            max_chars = AI_BUBBLE_MAX_CHARS

        # tk.Text kullanıyoruz — kullanıcı metni mouse ile seçebilsin
        box_width, box_height = _measure_bubble(content or " ", max_chars)
        content_lbl = tk.Text(
            bubble,
            bg=bubble["bg"],
            fg=fg_txt,
            font=F_BUBBLE,
            relief=tk.FLAT, bd=0,
            wrap=tk.WORD,
            width=box_width,
            height=box_height,
            padx=10, pady=8,
            cursor="xterm",
            exportselection=True,
            selectbackground="#bfdbfe",
            selectforeground="#1e293b",
            highlightthickness=0,
            takefocus=0,
            spacing3=2,
        )
        content_lbl.insert("1.0", content or " ")
        content_lbl.configure(state=tk.DISABLED)
        content_lbl.pack(anchor="w")
        for widget in (outer, bubble, content_lbl):
            self._bind_scroll_proxy(widget)
        if not is_user:
            for widget in (row, av):
                self._bind_scroll_proxy(widget)

        if ts:
            ts_row = tk.Frame(bubble, bg=bubble["bg"])
            ts_row.pack(fill=tk.X, padx=14, pady=(0, 8))
            stamp = tk.Label(ts_row, text=ts, bg=bubble["bg"], fg=ts_fg, font=F_STAMP, anchor="e")
            stamp.pack(side=tk.RIGHT)
            self._bind_scroll_proxy(ts_row)
            self._bind_scroll_proxy(stamp)

        self._scroll_to_bottom()
        return BubbleRef(content_label=content_lbl, frame=bubble)

    def _append_message(self, role: str, content: str, ts: Optional[str] = None) -> None:
        stamp = ts or _now_hm()
        self.messages.append({"role": role, "content": content, "ts": stamp})
        self._add_bubble(role, content, stamp)

    def _render_history(self) -> None:
        for child in self.messages_frame.winfo_children():
            child.destroy()
        for msg in self.messages:
            role = msg.get("role", "")
            content = msg.get("content", "")
            ts = str(msg.get("ts", _now_hm()))
            if role in {"user", "assistant"}:
                self._add_bubble(role, content, ts)

    def _compact_messages(self, max_messages: int = 30) -> list[dict[str, str]]:
        tail = self.messages[-max_messages:] if len(self.messages) > max_messages else self.messages
        payload = [{"role": "system", "content": _build_system_prompt()}]
        for msg in tail:
            role = msg.get("role")
            content = msg.get("content", "")
            if role in {"user", "assistant"}:
                payload.append({"role": role, "content": content})
        return payload

    def _should_use_direct_model(self, text: str) -> bool:
        # Hizli modda kisa/tek satir sorulari direkt modele yonlendiriyoruz.
        cleaned = text.strip()
        if not self.fast_mode:
            return False
        if not cleaned or "\n" in cleaned:
            return False
        if len(cleaned) > 120:
            return False
        if cleaned.startswith("/"):
            return False
        return True

    def _clear_chat(self) -> None:
        self.messages = []
        self._render_history()
        self._append_message("assistant", "Sohbet temizlendi. Hazırım.")
        self._save_memory()

    def _set_busy(self, value: bool) -> None:
        self.busy = value
        state = tk.DISABLED if value else tk.NORMAL
        self.input_entry.configure(state=state)
        self.send_btn.configure(state=state)
        self.file_btn.configure(state=state)
        if value:
            self.status_text.set("Yazıyor...")
            self.send_btn.configure(text="…", fg="#bfdbfe")
            self.send_btn.pack_forget()
            self.stop_btn.pack(side=tk.LEFT, padx=(2, 0), ipady=2)
        else:
            self._stop_event.clear()
            self.status_text.set(self._idle_status_text())
            self.stop_btn.pack_forget()
            self.send_btn.pack(side=tk.LEFT, padx=(2, 0), ipady=2)
            self.send_btn.configure(text="↑", fg="white")
            self.input_entry.focus_set()
            if not self.input_var.get().strip():
                self._apply_placeholder()

    def _on_stop(self) -> None:
        """Kullanıcı durdurma butonuna bastı — isteği iptal et."""
        self._stop_event.set()
        self.event_queue.put(("error", "İstek kullanıcı tarafından iptal edildi."))

    def _save_memory(self) -> None:
        PANEL_MEMORY_PATH.parent.mkdir(parents=True, exist_ok=True)
        payload = {"messages": self.messages[-300:]}
        PANEL_MEMORY_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    def _load_memory(self) -> None:
        if not PANEL_MEMORY_PATH.exists():
            return
        try:
            payload = json.loads(PANEL_MEMORY_PATH.read_text(encoding="utf-8"))
            saved = payload.get("messages", [])
            if isinstance(saved, list):
                cleaned: list[dict[str, str]] = []
                for item in saved:
                    role = str(item.get("role", ""))
                    content = str(item.get("content", ""))
                    ts = str(item.get("ts", _now_hm()))
                    if role in {"user", "assistant"} and content:
                        cleaned.append({"role": role, "content": content, "ts": ts})
                self.messages = cleaned
        except Exception:
            self.messages = []

    def _send_text(self, text: str) -> None:
        self._append_message("user", text)
        self.pending_user_text = text
        self.current_assistant_ref = self._add_thinking_bubble()
        self.current_ai_text = ""
        self._stop_event.clear()
        self._set_busy(True)

        if self._should_use_direct_model(text):
            payload = self._compact_messages(max_messages=24)
            threading.Thread(target=self._call_model_stream, args=(payload,), daemon=True).start()
            return

        history = self.messages[-30:]
        threading.Thread(target=self._call_agent_reply, args=(text, history), daemon=True).start()

    def _send_automation_text(self, text: str) -> None:
        self._append_message("user", text)
        self.pending_user_text = text
        self.current_assistant_ref = self._add_thinking_bubble()
        self.current_ai_text = ""
        self._stop_event.clear()
        self._set_busy(True)

        history = self.messages[-40:]
        threading.Thread(target=self._call_project_automation, args=(history,), daemon=True).start()

    def _ingest_file(self, file_path: str) -> None:
        path = Path(file_path).expanduser()
        if not path.exists() or not path.is_file():
            self._append_message("assistant", f"Dosya bulunamadi: {file_path}")
            self._save_memory()
            return

        try:
            content = _read_file_preview(path)
        except Exception as exc:
            self._append_message("assistant", f"Dosya okunamadi: {exc}")
            self._save_memory()
            return

        prompt = (
            f"Dosya eklendi: {path.name}\n"
            f"Yol: {path}\n"
            "Icerik:\n"
            f"{content}\n\n"
            "Bu dosyayi analiz et ve kisa ozet ver."
        )
        self._send_text(prompt)

    def _on_drop(self, event: Any) -> None:
        if self.busy:
            return
        raw = str(getattr(event, "data", "")).strip()
        if not raw:
            return
        paths = _parse_drop_paths(raw)
        if not paths:
            return
        self._ingest_file(paths[0])

    def _select_file(self) -> None:
        if self.busy:
            return
        selected = filedialog.askopenfilename(title="Analiz icin dosya sec")
        if selected:
            self._ingest_file(selected)

    def _call_model_stream(self, messages: list[dict[str, str]]) -> None:
        timeout_s = STREAM_TIMEOUT_FAST if self.fast_mode else STREAM_TIMEOUT_NORMAL
        try:
            final_text = ""
            for part in stream_chat(
                model=MODEL_NAME,
                messages=messages,
                options=MODEL_OPTIONS,
                timeout=timeout_s,
            ):
                if self._stop_event.is_set():
                    break
                final_text += part
                self.event_queue.put(("chunk", part))
            if self._stop_event.is_set():
                return
            self.event_queue.put(("done", final_text.strip() or "Hazirim."))
        except requests.HTTPError as exc:
            status = exc.response.status_code if exc.response is not None else "?"
            reason = exc.response.text[:200] if exc.response is not None else str(exc)
            self.event_queue.put(("error", f"HTTP {status}: {reason}"))
        except requests.RequestException as exc:
            self.event_queue.put(("error", f"Baglanti hatasi: {exc}"))
        except TimeoutError:
            self.event_queue.put(("error", f"Model {timeout_s} saniyede yanit vermedi. Tekrar dene."))
        except Exception as exc:
            self.event_queue.put(("error", str(exc)))

    def _call_agent_reply(self, goal: str, history: list[dict[str, str]]) -> None:
        try:
            dervis_core = _load_dervis_core_module()
            learning_context = ""
            try:
                learning_context = str(dervis_core._get_learning_context(goal))
            except Exception:
                learning_context = _load_learning_context_text()
            step_limit = AGENT_MAX_STEPS_FAST if self.fast_mode else AGENT_MAX_STEPS_NORMAL
            answer = asyncio.run(
                dervis_core.run_goal(
                    goal,
                    max_steps=step_limit,
                    echo=False,
                    history=history,
                    learning_context=learning_context,
                    user_profile=_load_user_profile_text(),
                )
            )
            if self._stop_event.is_set():
                return
            self.event_queue.put(("done", str(answer).strip() or "Hazirim."))
        except Exception as exc:
            self.event_queue.put(("error", f"Agent hatasi: {exc}"))

    def _call_project_automation(self, history: list[dict[str, str]]) -> None:
        try:
            automation = _load_otonom_proje_module()
            answer = automation.start_from_chat(history)
            if self._stop_event.is_set():
                return
            self.event_queue.put(("done", str(answer).strip() or "Otonom proje hazir."))
        except Exception as exc:
            self.event_queue.put(("error", f"Otonom proje hatasi: {exc}"))

    def _on_send(self, event: Any = None) -> None:
        if self.busy:
            return

        raw = self.input_var.get()
        # Placeholder sizintisi: kullanici focus_in tetiklemeden yazdi
        if self.placeholder_active:
            self.placeholder_active = False
            self.input_entry.configure(fg="#1e293b")
            if raw.startswith(self.placeholder_text):
                raw = raw[len(self.placeholder_text):]
            elif raw == self.placeholder_text:
                raw = ""

        text = raw.strip()
        self.input_var.set("")
        if not text:
            self._apply_placeholder()
            return
        if text.lower() in {"/hizli", "/fast"}:
            self._set_fast_mode(True)
            self._append_message("assistant", "Hızlı mod açıldı. Daha kısa düşünür, daha hızlı yanıt verir.")
            self._save_memory()
            return
        if text.lower() in {"/normal", "/standart"}:
            self._set_fast_mode(False)
            self._append_message("assistant", "Normal moda dönüldü. Daha derin analiz yapar.")
            self._save_memory()
            return
        if text.lower() in {"/mod", "/mode"}:
            label = "Hızlı" if self.fast_mode else "Normal"
            self._append_message("assistant", f"Aktif mod: {label}")
            self._save_memory()
            return
        if text.lower() == "/model":
            self._append_message("assistant", get_identity_label(MODEL_NAME))
            self._save_memory()
            return
        if text.lower() in {"/temizle", "/clear"}:
            self._clear_chat()
            return

        if _is_autonomous_project_start(text):
            self._send_automation_text(text)
            return

        self._send_text(text)

    def _poll_events(self) -> None:
        try:
            while True:
                try:
                    event, payload = self.event_queue.get_nowait()
                except queue.Empty:
                    break

                try:
                    if event == "chunk":
                        part = str(payload)
                        self.current_ai_text += part
                        if self.current_assistant_ref is None:
                            self.current_assistant_ref = self._add_bubble("assistant", "", _now_hm())
                        ref = self.current_assistant_ref
                        self._set_text_widget_content(ref.content_label, self.current_ai_text, bg=C_BUBBLE_AI, fg=C_TXT_AI)
                        ref.frame.configure(bg=C_BUBBLE_AI)
                        self._scroll_to_bottom()
                    elif event == "done":
                        final_text = str(payload)
                        if self.current_assistant_ref is not None:
                            ref = self.current_assistant_ref
                            try:
                                self._set_text_widget_content(ref.content_label, final_text, bg=C_BUBBLE_AI, fg=C_TXT_AI)
                                ref.frame.configure(bg=C_BUBBLE_AI)
                            except Exception:
                                pass
                        else:
                            self._add_bubble("assistant", final_text, _now_hm())
                        self.messages.append({"role": "assistant", "content": final_text, "ts": _now_hm()})
                        if self.pending_user_text:
                            try:
                                dervis_core = _load_dervis_core_module()
                                dervis_core._record_learning(
                                    kind="dialog_pair",
                                    content=f"Soru: {self.pending_user_text}\nCevap: {final_text}",
                                    source="panel_chat",
                                )
                            except Exception:
                                pass
                        self.pending_user_text = ""
                        self.current_assistant_ref = None
                        self.current_ai_text = ""
                        self._set_busy(False)
                        self._save_memory()
                    elif event == "error":
                        error_text = f"⚠️  {payload}"
                        if self.current_assistant_ref is not None:
                            try:
                                self._set_text_widget_content(
                                    self.current_assistant_ref.content_label,
                                    error_text,
                                    bg=C_BUBBLE_AI,
                                    fg="#ef4444",
                                )
                            except Exception:
                                pass
                        else:
                            self._append_message("assistant", error_text)
                        self.messages.append({"role": "assistant", "content": error_text, "ts": _now_hm()})
                        self.pending_user_text = ""
                        self.current_assistant_ref = None
                        self.current_ai_text = ""
                        self._set_busy(False)
                        self._save_memory()
                except Exception:
                    # Herhangi bir event işleme hatası tüm döngüyü öldürmesin
                    traceback.print_exc()
                    self.current_assistant_ref = None
                    self.current_ai_text = ""
                    if self.busy:
                        self._set_busy(False)
        finally:
            # Polling her zaman devam eder
            self.root.after(50, self._poll_events)

    def _on_close(self) -> None:
        self._koordinator_stop.set()
        self._save_memory()
        self.root.destroy()

    def run(self) -> None:
        self.root.mainloop()


def ensure_backend_running() -> None:
    ensure_local_ollama_running()


def main() -> None:
    ensure_backend_running()
    panel = DervisPanel()
    panel.run()


if __name__ == "__main__":
    main()
