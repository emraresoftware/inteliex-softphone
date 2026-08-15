#!/usr/bin/env python3
import datetime
import hmac
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = "127.0.0.1"
PORT = int(os.environ.get("DIAGNOSTICS_PORT", "8765"))
INGEST_TOKEN = os.environ["DIAGNOSTICS_INGEST_TOKEN"]
ADMIN_TOKEN = os.environ["DIAGNOSTICS_ADMIN_TOKEN"]
LOG_DIR = Path(os.environ.get("DIAGNOSTICS_LOG_DIR", "/var/log/inteliex-softphone"))
MAX_BODY = 64 * 1024
MAX_EVENTS = 40


def authorized(header, token):
    expected = f"Bearer {token}"
    return hmac.compare_digest(header or "", expected)


def today_file():
    return LOG_DIR / f"events-{datetime.datetime.now(datetime.timezone.utc):%Y-%m-%d}.ndjson"


class Handler(BaseHTTPRequestHandler):
    server_version = "InteliexDiagnostics/1"

    def send_json(self, status, payload):
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def do_POST(self):
        if self.path != "/ingest":
            return self.send_json(404, {"success": False})
        if not authorized(self.headers.get("Authorization"), INGEST_TOKEN):
            return self.send_json(401, {"success": False})
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY:
            return self.send_json(413, {"success": False})
        try:
            payload = json.loads(self.rfile.read(length))
            events = payload.get("events")
            if not isinstance(events, list) or not events or len(events) > MAX_EVENTS:
                raise ValueError("invalid events")
            received = datetime.datetime.now(datetime.timezone.utc).isoformat()
            lines = []
            for event in events:
                if not isinstance(event, dict):
                    raise ValueError("invalid event")
                event["receivedAt"] = received
                lines.append(json.dumps(event, ensure_ascii=False, separators=(",", ":")))
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            with today_file().open("a", encoding="utf-8") as stream:
                stream.write("\n".join(lines) + "\n")
            self.send_json(202, {"success": True, "accepted": len(lines)})
        except (ValueError, TypeError, json.JSONDecodeError):
            self.send_json(400, {"success": False})

    def do_GET(self):
        if self.path == "/health":
            return self.send_json(200, {"success": True})
        if not self.path.startswith("/events"):
            return self.send_json(404, {"success": False})
        if not authorized(self.headers.get("Authorization"), ADMIN_TOKEN):
            return self.send_json(401, {"success": False})
        lines = []
        for path in sorted(LOG_DIR.glob("events-*.ndjson"), reverse=True)[:3]:
            lines.extend(path.read_text(encoding="utf-8").splitlines())
            if len(lines) >= 500:
                break
        events = [json.loads(line) for line in lines[-500:] if line.strip()]
        self.send_json(200, {"success": True, "events": events})

    def log_message(self, _format, *_args):
        return


if __name__ == "__main__":
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
