#!/usr/bin/env python3
"""
dervis — Dergah terminal CLI asistanı.

Kullanım:
  dervis status               Sistem sağlığı
  dervis sprint               Aktif sprint tablosu
  dervis ask "soru"           AI'ya hızlı soru
  dervis ask "soru" -f d.py   Dosya bağlamıyla soru
  dervis otonom "brief"       Sohbetten otonom proje başlat
  dervis review               Kod incelemesi
  dervis dispatch [opts]      Agent workspace güncelle
  dervis log [N]              Son N sohbet mesajını göster
  dervis mesaj ...            Dervişler arası kapalı devre mesajlaşma
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import click
import requests
from rich.columns import Columns
from rich.console import Console
from rich.markdown import Markdown
from rich.panel import Panel
from rich.spinner import Spinner
from rich.status import Status
from rich.table import Table
from rich.text import Text

# ── paths ────────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
AGENTS_DIR = ROOT / "agents"
BACKLOG_PATH = AGENTS_DIR / "backlog.json"
CHAT_MEMORY_DIR = ROOT / "data" / "chat_memory"
HANDOFFS_PATH = AGENTS_DIR / "handoffs.ndjson"

console = Console()

# ── helpers ───────────────────────────────────────────────────────────────────

def _add_scripts_to_path() -> None:
    s = str(SCRIPTS_DIR)
    if s not in sys.path:
        sys.path.insert(0, s)


def _ollama_info() -> tuple[bool, list[str]]:
    """Ollama durumu ve kurulu modeller. (ok, model_listesi)"""
    try:
        r = requests.get("http://127.0.0.1:11434/api/tags", timeout=4)
        if r.ok:
            models = [m["name"] for m in r.json().get("models", [])]
            return True, models
    except Exception:
        pass
    return False, []


def _panel_running() -> bool:
    try:
        result = subprocess.run(["pgrep", "-f", "dervis_panel.py"],
                                capture_output=True, timeout=5)
        return result.returncode == 0
    except Exception:
        return False


def _load_backlog() -> dict:
    if BACKLOG_PATH.exists():
        return json.loads(BACKLOG_PATH.read_text(encoding="utf-8"))
    return {}


def _active_sprint_data(bl: dict) -> tuple[str, list, dict]:
    """(sprint_id, tasks_list, rules) döner — eski ve yeni format destekler."""
    if bl.get("sprints"):
        sid = bl.get("activeSprint") or list(bl["sprints"].keys())[0]
        sd = bl["sprints"].get(sid, {})
        return sid, sd.get("tasks", []), sd.get("rules", {})
    return bl.get("sprint", "?"), bl.get("tasks", []), bl.get("rules", {})


def _get_active_model() -> str:
    _add_scripts_to_path()
    try:
        from llm_bridge import get_default_model_name, get_provider  # type: ignore
        return f"{get_default_model_name()} ({get_provider()})"
    except Exception:
        return "?"


def _stream_ai(query: str, system: str = "", timeout: int = 120) -> None:
    """Streaming AI cevabı; rich Markdown olarak yazar."""
    _add_scripts_to_path()
    try:
        from llm_bridge import get_default_model_name, stream_chat  # type: ignore
    except ImportError as e:
        console.print(f"[red]llm_bridge import hatası: {e}[/]")
        return

    model = get_default_model_name()
    messages: list[dict] = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": query})

    options = {"num_ctx": 8192, "temperature": 0.4, "top_p": 0.9}

    console.print()
    collected: list[str] = []
    try:
        for chunk in stream_chat(model=model, messages=messages, options=options, timeout=timeout):
            console.print(chunk, end="", markup=False, highlight=False)
            collected.append(chunk)
    except Exception as e:
        console.print(f"\n[red]AI hatası: {e}[/]")
        return
    console.print()  # newline after streaming

# ── status ────────────────────────────────────────────────────────────────────

@click.group(invoke_without_command=True)
@click.pass_context
def cli(ctx: click.Context) -> None:
    """🧿  Dergah — yerel AI geliştirici asistanı

    Direkt soru da sorabilirsin:  dervis "python'da list comprehension ne zaman kullanılır?"
    """
    if ctx.invoked_subcommand is None:
        click.echo(ctx.get_help())

@cli.command("status")
def cmd_status() -> None:
    """Sistem sağlık durumunu göster."""
    ollama_ok, models = _ollama_info()
    panel_ok = _panel_running()
    active_model = _get_active_model()

    # ── tablo ──
    t = Table(title="Dergah Sistem Durumu", expand=True, border_style="dim")
    t.add_column("Bileşen", style="bold")
    t.add_column("Durum")
    t.add_column("Detay")

    t.add_row(
        "Ollama",
        "[green]✓ çalışıyor[/]" if ollama_ok else "[red]✗ kapalı[/]",
        ", ".join(models[:5]) if models else "model yok",
    )
    t.add_row(
        "Aktif Model",
        "[cyan]●[/]",
        active_model,
    )
    t.add_row(
        "Derviş Panel",
        "[green]✓ çalışıyor[/]" if panel_ok else "[yellow]○ kapalı[/]",
        "tkinter GUI" if panel_ok else "başlatmak için: dervis panel",
    )

    # backlog özeti
    bl = _load_backlog()
    sid, tasks, _ = _active_sprint_data(bl)
    in_prog = sum(1 for t_ in tasks if t_.get("status") == "in_progress")
    todo_c = sum(1 for t_ in tasks if t_.get("status") == "todo")
    done_c = sum(1 for t_ in tasks if t_.get("status") == "done")
    t.add_row(
        "Sprint",
        f"[bold]{sid}[/]",
        f"in_progress: {in_prog}  todo: {todo_c}  done: {done_c}",
    )

    # handoff sayısı
    hcount = 0
    if HANDOFFS_PATH.exists():
        hcount = sum(1 for _ in HANDOFFS_PATH.read_text(encoding="utf-8").splitlines() if _.strip())
    t.add_row("Dispatch log", "[dim]📋[/]", f"{hcount} handoff kaydı")

    console.print(t)


# ── sprint ────────────────────────────────────────────────────────────────────

_STATUS_STYLE = {
    "in_progress": "[bold yellow]⟳ in_progress[/]",
    "todo":        "[dim]○ todo[/]",
    "done":        "[green]✓ done[/]",
    "blocked":     "[red]⊘ blocked[/]",
}


@cli.command("sprint")
@click.option("--all", "show_all", is_flag=True, help="Tüm görevleri göster (done dahil)")
def cmd_sprint(show_all: bool) -> None:
    """Aktif sprint backlog tablosunu göster."""
    bl = _load_backlog()
    if not bl:
        console.print("[yellow]agents/backlog.json bulunamadı.[/]")
        return

    sid, tasks, _ = _active_sprint_data(bl)
    if not show_all:
        tasks = [t for t in tasks if t.get("status") != "done"]

    t = Table(
        title=f"Sprint {sid} — Görev Listesi",
        expand=True,
        border_style="dim",
    )
    t.add_column("ID", style="bold cyan", no_wrap=True)
    t.add_column("Başlık", ratio=3)
    t.add_column("Sahip", style="magenta")
    t.add_column("Durum")
    t.add_column("Bağımlı")

    for task in tasks:
        deps = ", ".join(task.get("dependsOn", [])) or "—"
        status_str = _STATUS_STYLE.get(task.get("status", ""), task.get("status", ""))
        t.add_row(
            task.get("id", "?"),
            task.get("title", ""),
            task.get("owner", "—"),
            status_str,
            deps,
        )

    console.print(t)

    # iş kartı özeti
    cards_dir = AGENTS_DIR / "cards"
    for task in tasks:
        tid = task.get("id", "")
        card = cards_dir / f"{tid}-is-karti.md"
        if card.exists():
            lines = card.read_text(encoding="utf-8").splitlines()
            todos = [l.strip() for l in lines if l.strip().startswith("- [ ]")]
            dones = [l.strip() for l in lines if l.strip().startswith("- [x]")]
            if todos or dones:
                console.print(
                    f"  [dim]{tid}[/] → {len(dones)}/{len(todos)+len(dones)} madde tamamlandı"
                )


# ── ask ───────────────────────────────────────────────────────────────────────

@cli.command("ask")
@click.argument("question")
@click.option("--file", "-f", "filepath", default=None, type=click.Path(exists=True),
              help="Bağlam dosyası ekle")
@click.option("--system", "-s", default=None, help="Özel sistem prompt'u")
def cmd_ask(question: str, filepath: str | None, system: str | None) -> None:
    """AI'ya hızlı soru sor (streaming cevap)."""
    context_note = ""
    if filepath:
        path = Path(filepath)
        content = path.read_text(encoding="utf-8", errors="replace")[:8000]
        context_note = f"\n\n[dim]📄 Bağlam: {path.name}[/]"
        question = f"Dosya: {path.name}\n\n```\n{content}\n```\n\n{question}"

    sys_prompt = system or (
        "Sen Dervis, yerel bir AI kod asistanısın. Türkçe cevaplar ver. "
        "Kısa ve net ol. Kod önerirken doğrudan kod bloğu yaz."
    )

    console.print(Panel(f"[bold]{question[:120]}{'...' if len(question)>120 else ''}[/]{context_note}",
                        title="[cyan]Soru[/]", border_style="cyan"))
    console.print("[dim cyan]▸ Yanıt:[/]")
    _stream_ai(question, system=sys_prompt)


# ── review ────────────────────────────────────────────────────────────────────

@cli.command("review")
@click.argument("filepath", type=click.Path(exists=True))
@click.option("--focus", "-f", default=None, help="Odaklanılacak konu (güvenlik, performans, vb.)")
def cmd_review(filepath: str, focus: str | None) -> None:
    """Dosyayı AI kod incelemesinden geçir."""
    path = Path(filepath)
    content = path.read_text(encoding="utf-8", errors="replace")
    if len(content) > 10000:
        console.print(f"[yellow]Dosya büyük ({len(content)} karakter), ilk 10000 karakter inceleniyor.[/]")
        content = content[:10000]

    focus_note = f"\nÖzellikle şuna odaklan: {focus}" if focus else ""
    prompt = (
        f"Şu Python dosyasını incele ve geliştirme önerilerini listele.\n"
        f"Dosya adı: {path.name}\n{focus_note}\n\n"
        f"Şunlara bak: hata riski, güvenlik açığı, performans, okunabilirlik, eksik hata yönetimi.\n"
        f"Her bulgu için: [Başlık] → Açıklama → Öneri formatını kullan.\n\n"
        f"```python\n{content}\n```"
    )

    sys_prompt = (
        "Sen kıdemli bir Python geliştiricisisin. Türkçe, maddeler halinde, pratik öneriler ver. "
        "Kod kalitesi ve güvenlik açıklarına odaklan."
    )

    console.print(Panel(f"[bold]{path.name}[/] — {len(content)} karakter",
                        title="[green]Kod İncelemesi[/]", border_style="green"))
    _stream_ai(prompt, system=sys_prompt, timeout=180)


# ── dispatch ──────────────────────────────────────────────────────────────────

@cli.command("dispatch")
@click.option("--all", "all_tasks", is_flag=True, help="todo görevleri de dahil et")
@click.option("--role", default=None, help="Belirli ajan rolü (ops, core, vb.)")
@click.option("--dry-run", is_flag=True, help="Yazmadan önizleme göster")
def cmd_dispatch(all_tasks: bool, role: str | None, dry_run: bool) -> None:
    """agents/backlog.json görevlerini ajan workspace'lerine yaz."""
    dispatch_js = AGENTS_DIR / "dispatch.js"
    if not dispatch_js.exists():
        console.print("[red]agents/dispatch.js bulunamadı.[/]")
        return

    cmd = ["node", str(dispatch_js)]
    if all_tasks:
        cmd.append("--all")
    if role:
        cmd += ["--role", role]
    if dry_run:
        cmd.append("--dry-run")

    console.print(f"[dim]$ {' '.join(cmd)}[/]")
    result = subprocess.run(cmd, capture_output=False, cwd=str(ROOT))
    if result.returncode != 0:
        console.print("[red]dispatch hata ile çıktı.[/]")


# ── log ───────────────────────────────────────────────────────────────────────

@cli.command("log")
@click.argument("n", default=10, type=int)
@click.option("--search", "-s", default=None, help="Mesajlarda ara")
def cmd_log(n: int, search: str | None) -> None:
    """Son sohbet mesajlarını göster."""
    latest = CHAT_MEMORY_DIR / "latest.json"
    if not latest.exists():
        console.print("[yellow]data/chat_memory/latest.json bulunamadı.[/]")
        return

    data = json.loads(latest.read_text(encoding="utf-8"))
    messages = data if isinstance(data, list) else data.get("messages", [])

    if search:
        messages = [m for m in messages if search.lower() in str(m.get("content", "")).lower()]

    messages = messages[-n:]
    t = Table(title=f"Son {len(messages)} sohbet mesajı", expand=True, border_style="dim")
    t.add_column("Rol", style="bold", no_wrap=True, width=10)
    t.add_column("İçerik")

    for msg in messages:
        role_ = msg.get("role", "?")
        content_ = str(msg.get("content", ""))[:300]
        if len(str(msg.get("content", ""))) > 300:
            content_ += "…"
        color = "cyan" if role_ == "user" else "green"
        t.add_row(f"[{color}]{role_}[/]", content_)

    console.print(t)


# ── mesaj ─────────────────────────────────────────────────────────────────────

@cli.group("mesaj")
def cmd_mesaj() -> None:
    """Dervişler arası kapalı devre mesajlaşma."""


@cmd_mesaj.command("gonder")
@click.option("--from-agent", "from_agent", required=True, help="Gönderen ajan id")
@click.option("--to-agent", "to_agent", required=True, help="Hedef ajan id")
@click.option("--icerik", required=True, help="Mesaj içeriği")
def cmd_mesaj_gonder(from_agent: str, to_agent: str, icerik: str) -> None:
    """Bir ajandan diğerine mesaj gönder."""
    _add_scripts_to_path()
    try:
        import dervis_mesajlasma as dm  # type: ignore
        mid = dm.send_message(from_agent, to_agent, icerik)
    except Exception as exc:
        console.print(f"[red]Mesaj gönderilemedi: {exc}[/]")
        return
    console.print(f"[green]Mesaj gönderildi[/] id={mid} [dim]{from_agent} -> {to_agent}[/]")


@cmd_mesaj.command("yayin")
@click.option("--from-agent", "from_agent", required=True, help="Gönderen ajan id")
@click.option("--icerik", required=True, help="Mesaj içeriği")
def cmd_mesaj_yayin(from_agent: str, icerik: str) -> None:
    """Bir ajandan tüm diğer ajanlara yayın mesajı gönder."""
    _add_scripts_to_path()
    try:
        import dervis_mesajlasma as dm  # type: ignore
        ids = dm.broadcast_message(from_agent, icerik)
    except Exception as exc:
        console.print(f"[red]Yayın mesajı gönderilemedi: {exc}[/]")
        return
    console.print(f"[green]Yayın gönderildi[/] toplam={len(ids)}")


@cmd_mesaj.command("kutu")
@click.option("--agent", required=True, help="Ajan id")
@click.option("--all", "show_all", is_flag=True, help="Okunan mesajları da göster")
@click.option("--limit", default=20, show_default=True, type=int, help="Maksimum mesaj")
def cmd_mesaj_kutu(agent: str, show_all: bool, limit: int) -> None:
    """Ajan inbox mesajlarını göster."""
    _add_scripts_to_path()
    try:
        import dervis_mesajlasma as dm  # type: ignore
        rows = dm.list_inbox(agent, limit=limit, include_acked=show_all)
    except Exception as exc:
        console.print(f"[red]Mesaj kutusu okunamadı: {exc}[/]")
        return

    if not rows:
        console.print("[yellow]Mesaj yok.[/]")
        return

    t = Table(title=f"Mesaj Kutusu — {agent}", expand=True, border_style="dim")
    t.add_column("ID", style="cyan", no_wrap=True)
    t.add_column("Gönderen", style="magenta", no_wrap=True)
    t.add_column("Zaman", style="dim", no_wrap=True)
    t.add_column("Durum", no_wrap=True)
    t.add_column("İçerik")
    for row in rows:
        acked = bool(row.get("acked"))
        status = "[green]okundu[/]" if acked else "[yellow]yeni[/]"
        content = str(row.get("content", "")).strip()
        if len(content) > 180:
            content = content[:180] + "..."
        t.add_row(
            str(row.get("id", "-")),
            str(row.get("from", "-")),
            str(row.get("ts", "-")),
            status,
            content,
        )
    console.print(t)


@cmd_mesaj.command("okundu")
@click.option("--agent", required=True, help="Ajan id")
@click.option("--id", "message_id", required=True, help="Mesaj id")
@click.option("--not", "note", default="okundu", show_default=True, help="Kısa durum notu")
def cmd_mesaj_okundu(agent: str, message_id: str, note: str) -> None:
    """Mesajı okundu olarak işaretle."""
    _add_scripts_to_path()
    try:
        import dervis_mesajlasma as dm  # type: ignore
        dm.ack_message(agent, message_id, note)
    except Exception as exc:
        console.print(f"[red]Okundu işaretlenemedi: {exc}[/]")
        return
    console.print(f"[green]İşaretlendi[/] agent={agent} id={message_id}")


@cmd_mesaj.command("koordinator")
@click.option("--agent", default="yonetici", show_default=True, help="Koordinator olarak davranacak ajan")
@click.option("--limit", default=20, show_default=True, type=int, help="Her turda işlenecek maksimum yeni mesaj")
@click.option("--watch", is_flag=True, help="Sürekli dinle ve otomatik yanıtla")
@click.option("--interval", default=20, show_default=True, type=int, help="Watch modunda tur aralığı (sn)")
@click.option("--dry-run", is_flag=True, help="Yazmadan ne yapacağını göster")
def cmd_mesaj_koordinator(agent: str, limit: int, watch: bool, interval: int, dry_run: bool) -> None:
    """Soru/onay mesajlarını otomatik organize eden koordinator."""
    _add_scripts_to_path()
    try:
        import dervis_koordinator as dk  # type: ignore
    except Exception as exc:
        console.print(f"[red]Koordinator import hatası: {exc}[/]")
        return

    if watch:
        console.print(f"[cyan]Koordinator watch başladı[/] agent={agent} interval={interval}s")
        try:
            dk.run_loop(agent, interval_sec=interval, limit=limit, dry_run=dry_run)
        except KeyboardInterrupt:
            console.print("\n[yellow]Koordinator durduruldu.[/]")
        return

    try:
        stats = dk.process_once(agent, limit=limit, dry_run=dry_run)
    except Exception as exc:
        console.print(f"[red]Koordinator çalıştırılamadı: {exc}[/]")
        return

    mode = "dry-run" if dry_run else "aktif"
    console.print(
        f"[green]Koordinator tamamlandı[/] mode={mode} "
        f"checked={stats.checked} acked={stats.acked} replied={stats.replied}"
    )


# ── panel ─────────────────────────────────────────────────────────────────────

@cli.command("panel")
@click.option("--hizli", is_flag=True, help="Paneli hızlı modda başlat")
@click.option("--normal", is_flag=True, help="Paneli normal modda başlat")
def cmd_panel(hizli: bool, normal: bool) -> None:
    """Derviş Panel GUI'yi başlat."""
    if hizli and normal:
        console.print("[red]Aynı anda --hizli ve --normal kullanılamaz.[/]")
        return

    panel_py = SCRIPTS_DIR / "dervis_panel.py"
    if not panel_py.exists():
        console.print(f"[red]{panel_py} bulunamadı.[/]")
        return
    python = str(ROOT / ".venv" / "bin" / "python3.14")
    if not Path(python).exists():
        python = sys.executable

    env = os.environ.copy()
    if hizli:
        env["DERGAH_PANEL_FAST_MODE"] = "1"
    elif normal:
        env["DERGAH_PANEL_FAST_MODE"] = "0"

    mode_label = "hizli" if hizli else "normal" if normal else "varsayilan"
    console.print(f"[dim]Derviş Panel başlatılıyor ({python}) — mod: {mode_label}...[/]")
    subprocess.Popen([python, str(panel_py)], env=env)
    console.print("[green]Panel başlatıldı.[/]")


# ── otonom ───────────────────────────────────────────────────────────────────

@cli.command("otonom")
@click.argument("brief", nargs=-1)
@click.option("--desktop-root", default=None, help="Proje kökünün yazılacağı dizin (varsayılan: ~/Desktop)")
@click.option("--no-open", is_flag=True, help="VS Code pencerelerini otomatik açma")
@click.option("--no-paste", is_flag=True, help="İlk prompt'u chat alanına otomatik yapıştırma")
def cmd_otonom(brief: tuple[str, ...], desktop_root: str | None, no_open: bool, no_paste: bool) -> None:
    """Sohbet brifinden otonom proje klasörü + agent workspace'leri üret."""
    text = " ".join(brief).strip()
    if not text:
        console.print("[yellow]Kullanım: dervis otonom \"proje kısa tanımı\"[/]")
        return

    _add_scripts_to_path()
    try:
        import emare_otonom_proje as otonom  # type: ignore
    except Exception as exc:
        console.print(f"[red]emare_otonom_proje import hatası: {exc}[/]")
        return

    messages = [
        {"role": "user", "content": text},
        {"role": "assistant", "content": "Projenin ana hatlarini netlestirelim."},
        {"role": "user", "content": "Yazmaya basla"},
    ]

    console.print("[cyan]▸ Otonom proje akışı başlatılıyor...[/]")
    result = otonom.build_autonomous_project(
        messages,
        desktop_root=desktop_root,
        open_workspaces=not no_open,
        auto_paste=not no_paste,
    )

    spec = result.get("spec", {})
    ws = result.get("workspace_result", {})
    table = Table(title="Otonom Proje Sonucu", expand=True, border_style="dim")
    table.add_column("Alan", style="bold")
    table.add_column("Değer")
    table.add_row("Proje", str(spec.get("project_name", "-")))
    table.add_row("Slug", str(spec.get("project_slug", "-")))
    table.add_row("Şablon", str(spec.get("template", "-")))
    table.add_row("Klasör", str(result.get("root_dir", "-")))
    table.add_row("Dispatch", "OK" if result.get("dispatch_ok") else "HATA")
    table.add_row("Açılan Workspace", ", ".join(ws.get("opened", [])) or "-")
    table.add_row("Prompt Yapıştırılan", ", ".join(ws.get("pasted", [])) or "-")
    table.add_row("Açılamayan", ", ".join(ws.get("failed", [])) or "-")
    console.print(table)


# ── commit ────────────────────────────────────────────────────────────────────

@cli.command("commit")
@click.option("--push", is_flag=True, help="Commit sonrası git push yap")
def cmd_commit(push: bool) -> None:
    """Staged değişiklikler için AI ile commit mesajı oluştur."""
    result = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--staged"],
        capture_output=True, text=True
    )
    diff = result.stdout.strip()
    if not diff:
        console.print("[yellow]Staged değişiklik yok. `git add` ile dosyaları ekle.[/]")
        return

    if len(diff) > 8000:
        diff = diff[:8000] + "\n... (kesildi)"

    prompt = (
        "Aşağıdaki git diff'ten uygun bir commit mesajı üret.\n"
        "Format: `tip: kısa özet (maks 72 karakter)`\n"
        "Tipler: feat, fix, refactor, docs, chore, test\n"
        "Sonra 2-4 madde halinde değişiklikleri açıkla.\n\n"
        f"```diff\n{diff}\n```\n\n"
        "SADECE commit mesajını yaz, başka açıklama ekleme."
    )

    sys_prompt = "Sen bir senior yazılım mühendisisin. Türkçe ve İngilizce commit mesajı üretebilirsin. Kompakt ol."

    console.print(Panel(f"{len(diff.splitlines())} satır diff", title="[yellow]Commit Mesajı Oluşturuluyor[/]",
                        border_style="yellow"))
    _stream_ai(prompt, system=sys_prompt)

    if push:
        console.print("\n[dim]Push için `git push origin <branch>` komutunu çalıştır.[/]")


# ── entry ─────────────────────────────────────────────────────────────────────

# Bilinen alt komutlar
_KNOWN_COMMANDS = {"status", "sprint", "ask", "review", "dispatch", "log", "mesaj", "panel", "otonom", "commit"}

if __name__ == "__main__":
    # İlk arg bilinen bir komut değilse ve - ile başlamıyorsa → bare soru olarak "ask"a yönlendir
    if len(sys.argv) > 1 and sys.argv[1] not in _KNOWN_COMMANDS and not sys.argv[1].startswith("-"):
        question = " ".join(sys.argv[1:])
        sys_prompt = (
            "Sen Dervis, yerel bir AI kod asistanısın. Türkçe cevaplar ver. "
            "Kısa ve net ol. Kod önerirken doğrudan kod bloğu yaz."
        )
        console.print(Panel(f"[bold]{question[:120]}[/]", title="[cyan]Soru[/]", border_style="cyan"))
        console.print("[dim cyan]▸ Yanıt:[/]")
        _stream_ai(question, system=sys_prompt)
    else:
        cli()
