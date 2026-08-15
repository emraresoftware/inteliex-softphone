from __future__ import annotations

import json
import os
import subprocess
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import ollama

MODEL_NAME = "qwen2.5-coder:14b"
HOST = "127.0.0.1"
PORT = 8765
ROOT_DIR = Path(__file__).resolve().parents[1]

MODEL_OPTIONS = {
    "num_ctx": 16384,
    "temperature": 0.4,
    "top_p": 0.9,
    "repeat_penalty": 1.1,
}

SYSTEM_PROMPT = (
    "Sen Dervis Widget adli yerel asistansin. "
    "Kimligin qwen2.5-coder:14b (Ollama, lokal, Apple M5 Pro). "
    "Kisa, net ve uygulamaya donuk Turkce cevap ver. "
    "Asla JSON action semasi basma; sadece dogal metin cevap ver."
)


def ensure_ollama_running() -> None:
  try:
    subprocess.run(["ollama", "list"], check=True, capture_output=True, text=True)
  except Exception:
    env = os.environ.copy()
    env.setdefault("OLLAMA_HOST", "[::]:11434")
    subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)


def _extract_plain_reply(text: str) -> str:
    stripped = text.strip()
    if not stripped:
        return "Hazirim."
    try:
        parsed = json.loads(stripped)
        if isinstance(parsed, dict):
            args = parsed.get("args", {})
            if isinstance(args, dict) and isinstance(args.get("answer"), str) and args["answer"].strip():
                return args["answer"].strip()
    except Exception:
        pass

    decoder = json.JSONDecoder()
    for i, ch in enumerate(stripped):
        if ch != "{":
            continue
        try:
            obj, _ = decoder.raw_decode(stripped[i:])
            if isinstance(obj, dict):
                args = obj.get("args", {})
                if isinstance(args, dict) and isinstance(args.get("answer"), str) and args["answer"].strip():
                    return args["answer"].strip()
        except Exception:
            continue
    return stripped


def generate_reply(message: str, history: list[dict[str, str]]) -> str:
    clean_history: list[dict[str, str]] = []
    for item in history[-20:]:
        role = item.get("role", "")
        content = item.get("content", "")
        if role in {"user", "assistant"} and isinstance(content, str):
            clean_history.append({"role": role, "content": content})

    messages = [{"role": "system", "content": SYSTEM_PROMPT}] + clean_history + [{"role": "user", "content": message}]

    response = ollama.chat(model=MODEL_NAME, messages=messages, options=MODEL_OPTIONS)
    content = response.get("message", {}).get("content", "")
    return _extract_plain_reply(content)


INDEX_HTML = """<!doctype html>
<html lang=\"tr\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>Dervis Widget</title>
  <style>
    :root {
      --bg: #f4f6fb;
      --panel: #ffffff;
      --text: #182433;
      --muted: #6b7a90;
      --brand: #0b6e4f;
      --brand-2: #14532d;
      --border: #d9e1ec;
      --shadow: 0 20px 45px rgba(24, 36, 51, 0.22);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif;
      background: radial-gradient(circle at 20% 10%, #e7eef9 0%, #f4f6fb 45%, #eef5f2 100%);
      color: var(--text);
    }
    .launcher {
      position: fixed;
      right: 24px;
      bottom: 24px;
      width: 66px;
      height: 66px;
      border: none;
      border-radius: 999px;
      background: linear-gradient(135deg, #0b6e4f, #14532d);
      color: #fff;
      font-size: 26px;
      box-shadow: var(--shadow);
      cursor: pointer;
      z-index: 20;
    }
    .widget {
      position: fixed;
      right: 24px;
      bottom: 102px;
      width: min(420px, calc(100vw - 30px));
      height: min(620px, calc(100vh - 140px));
      border-radius: 18px;
      overflow: hidden;
      border: 1px solid var(--border);
      background: var(--panel);
      box-shadow: var(--shadow);
      display: none;
      flex-direction: column;
      z-index: 19;
    }
    .widget.open { display: flex; }
    .header {
      padding: 14px 16px;
      background: linear-gradient(140deg, #0b6e4f, #14532d);
      color: #fff;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .header .title { font-weight: 700; letter-spacing: 0.2px; }
    .header .meta { font-size: 12px; opacity: 0.9; }
    .chat {
      flex: 1;
      overflow-y: auto;
      padding: 14px;
      background: #fbfcff;
    }
    .bubble {
      max-width: 86%;
      padding: 10px 12px;
      border-radius: 13px;
      margin: 0 0 10px 0;
      line-height: 1.4;
      font-size: 14px;
      white-space: pre-wrap;
      word-break: break-word;
    }
    .user { margin-left: auto; background: #d9e9ff; color: #113355; }
    .assistant { margin-right: auto; background: #e9f7ef; color: #123b2e; }
    .typing {
      margin-right: auto;
      padding: 9px 12px;
      border-radius: 12px;
      background: #edf2fa;
      color: var(--muted);
      font-size: 13px;
    }
    .composer {
      padding: 10px;
      display: flex;
      gap: 8px;
      border-top: 1px solid var(--border);
      background: #fff;
    }
    .composer input {
      flex: 1;
      border: 1px solid var(--border);
      border-radius: 11px;
      padding: 11px 12px;
      font-size: 14px;
      outline: none;
    }
    .composer button {
      border: none;
      border-radius: 11px;
      background: var(--brand);
      color: #fff;
      min-width: 82px;
      cursor: pointer;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <button id=\"launcher\" class=\"launcher\" title=\"Dervis\">✶</button>
  <section id=\"widget\" class=\"widget\">
    <header class=\"header\">
      <div>
        <div class=\"title\">Dervis Sohbet</div>
        <div class=\"meta\">qwen2.5-coder:14b (lokal)</div>
      </div>
      <button id=\"closeBtn\" style=\"border:none;background:transparent;color:white;font-size:20px;cursor:pointer;\">×</button>
    </header>
    <main id=\"chat\" class=\"chat\"></main>
    <form id=\"form\" class=\"composer\">
      <input id=\"input\" autocomplete=\"off\" placeholder=\"Bir mesaj yaz...\" />
      <button type=\"submit\">Gonder</button>
    </form>
  </section>
  <script>
    const launcher = document.getElementById('launcher');
    const widget = document.getElementById('widget');
    const closeBtn = document.getElementById('closeBtn');
    const form = document.getElementById('form');
    const input = document.getElementById('input');
    const chat = document.getElementById('chat');

    const history = [];
    let busy = false;

    function appendBubble(role, text) {
      const div = document.createElement('div');
      div.className = `bubble ${role}`;
      div.textContent = text;
      chat.appendChild(div);
      chat.scrollTop = chat.scrollHeight;
      return div;
    }

    function setTyping(show) {
      let node = document.getElementById('typing');
      if (show && !node) {
        node = document.createElement('div');
        node.id = 'typing';
        node.className = 'typing';
        node.textContent = 'Dervis dusunuyor...';
        chat.appendChild(node);
      }
      if (!show && node) {
        node.remove();
      }
      chat.scrollTop = chat.scrollHeight;
    }

    async function typeWriter(node, text) {
      node.textContent = '';
      for (const ch of text) {
        node.textContent += ch;
        chat.scrollTop = chat.scrollHeight;
        await new Promise(r => setTimeout(r, 4));
      }
    }

    launcher.addEventListener('click', () => {
      widget.classList.toggle('open');
      if (widget.classList.contains('open')) {
        input.focus();
      }
    });

    closeBtn.addEventListener('click', () => widget.classList.remove('open'));

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const text = input.value.trim();
      if (!text || busy) return;

      busy = true;
      input.value = '';
      appendBubble('user', text);
      history.push({ role: 'user', content: text });
      setTyping(true);

      try {
        const res = await fetch('/api/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: text, history }),
        });
        const data = await res.json();
        setTyping(false);
        const bubble = appendBubble('assistant', '');
        await typeWriter(bubble, data.reply || 'Yanitsiz dondu.');
        history.push({ role: 'assistant', content: data.reply || '' });
      } catch (err) {
        setTyping(false);
        appendBubble('assistant', 'Hata olustu: ' + String(err));
      } finally {
        busy = false;
      }
    });

    appendBubble('assistant', 'Merhaba, ben Dervis. Buradan anlik sohbet edebiliriz.');
  </script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html: str) -> None:
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path == "/" or self.path.startswith("/?"):
            self._send_html(INDEX_HTML)
            return
        if self.path == "/health":
            self._send_json({"ok": True, "model": MODEL_NAME})
            return
        self.send_error(404)

    def do_POST(self) -> None:
        if self.path != "/api/chat":
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8", errors="ignore")
        try:
            payload = json.loads(raw)
            message = str(payload.get("message", "")).strip()
            history = payload.get("history", [])
            if not isinstance(history, list):
                history = []
        except Exception:
            self._send_json({"error": "invalid_json"}, status=400)
            return

        if not message:
            self._send_json({"error": "empty_message"}, status=400)
            return

        try:
            reply = generate_reply(message, history)
            self._send_json({"reply": reply})
        except Exception as exc:
            self._send_json({"error": str(exc)}, status=500)

    def log_message(self, format: str, *args: Any) -> None:
        return


def main() -> None:
    ensure_ollama_running()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    url = f"http://{HOST}:{PORT}/"
    print(f"Dervis Widget calisiyor: {url}")
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
