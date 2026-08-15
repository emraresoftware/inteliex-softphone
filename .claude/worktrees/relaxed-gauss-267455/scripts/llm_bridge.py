from __future__ import annotations

import json
import os
import subprocess
from typing import Any, Iterable

import requests


DEFAULT_MODEL_NAME = os.getenv("DERGAH_MODEL_NAME", "qwen2.5-coder:14b")
DEFAULT_PROVIDER = os.getenv("DERGAH_LLM_PROVIDER", "ollama").strip().lower()
OLLAMA_CHAT_URL = os.getenv("DERGAH_OLLAMA_CHAT_URL", "http://127.0.0.1:11434/api/chat")
OPENAI_API_BASE = os.getenv("DERGAH_OPENAI_API_BASE", "http://127.0.0.1:52415/v1").rstrip("/")
OPENAI_API_KEY = os.getenv("DERGAH_OPENAI_API_KEY", "")
DEFAULT_TIMEOUT = int(os.getenv("DERGAH_LLM_TIMEOUT", "90"))
FALLBACK_TO_OLLAMA = os.getenv("DERGAH_LLM_FALLBACK_OLLAMA", "1").strip().lower() in {"1", "true", "yes", "on"}
FALLBACK_OLLAMA_MODEL = os.getenv("DERGAH_OLLAMA_FALLBACK_MODEL", "qwen2.5-coder:14b")


def get_default_model_name() -> str:
    return DEFAULT_MODEL_NAME


def get_provider() -> str:
    return DEFAULT_PROVIDER


def get_identity_label(model_name: str | None = None) -> str:
    model = model_name or get_default_model_name()
    provider = get_provider()
    if provider == "openai_compat":
        return f"{model} (OpenAI-compatible, remote)"
    return f"{model} (Ollama, lokal)"


def _extract_openai_message(payload: dict[str, Any]) -> str:
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        return ""
    message = choices[0].get("message", {})
    if isinstance(message, dict):
        return str(message.get("content", ""))
    return ""


def _build_openai_headers() -> dict[str, str]:
    headers = {"Content-Type": "application/json"}
    if OPENAI_API_KEY:
        headers["Authorization"] = f"Bearer {OPENAI_API_KEY}"
    return headers


def _fallback_model_name(original_model: str) -> str:
    if FALLBACK_OLLAMA_MODEL.strip():
        return FALLBACK_OLLAMA_MODEL.strip()
    # Exo/OpenAI model IDs are typically long names with '/'; Ollama usually uses short tags.
    if "/" in original_model:
        return "qwen2.5-coder:14b"
    return original_model


def _should_fallback(exc: Exception) -> bool:
    return FALLBACK_TO_OLLAMA and isinstance(exc, requests.RequestException)


def _ollama_chat(model: str, messages: list[dict[str, str]], options: dict[str, Any] | None = None) -> dict[str, Any]:
    # Import lazily so environments without ollama package can still run with openai_compat.
    import ollama  # noqa: PLC0415

    return ollama.chat(model=model, messages=messages, options=options or {})


def _openai_compat_chat(
    model: str,
    messages: list[dict[str, str]],
    options: dict[str, Any] | None = None,
    timeout: int = DEFAULT_TIMEOUT,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": False,
    }
    if options:
        for key in ("temperature", "top_p"):
            if key in options:
                payload[key] = options[key]

    response = requests.post(
        f"{OPENAI_API_BASE}/chat/completions",
        headers=_build_openai_headers(),
        json=payload,
        timeout=timeout,
    )
    response.raise_for_status()
    raw = response.json()
    content = _extract_openai_message(raw)
    return {
        "message": {"role": "assistant", "content": content},
        "raw": raw,
    }


def chat(
    model: str,
    messages: list[dict[str, str]],
    options: dict[str, Any] | None = None,
    timeout: int = DEFAULT_TIMEOUT,
) -> dict[str, Any]:
    provider = get_provider()
    if provider == "openai_compat":
        try:
            return _openai_compat_chat(model=model, messages=messages, options=options, timeout=timeout)
        except Exception as exc:
            if not _should_fallback(exc):
                raise
            return _ollama_chat(model=_fallback_model_name(model), messages=messages, options=options)
    return _ollama_chat(model=model, messages=messages, options=options)


def stream_chat(
    model: str,
    messages: list[dict[str, str]],
    options: dict[str, Any] | None = None,
    timeout: int = DEFAULT_TIMEOUT,
) -> Iterable[str]:
    provider = get_provider()
    if provider == "openai_compat":
        try:
            payload: dict[str, Any] = {
                "model": model,
                "messages": messages,
                "stream": True,
            }
            if options:
                for key in ("temperature", "top_p"):
                    if key in options:
                        payload[key] = options[key]

            with requests.post(
                f"{OPENAI_API_BASE}/chat/completions",
                headers=_build_openai_headers(),
                json=payload,
                timeout=timeout,
                stream=True,
            ) as response:
                response.raise_for_status()
                for raw_line in response.iter_lines(decode_unicode=True):
                    if not raw_line:
                        continue
                    line = raw_line.strip()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        obj = json.loads(data)
                    except json.JSONDecodeError:
                        continue
                    choices = obj.get("choices")
                    if not isinstance(choices, list) or not choices:
                        continue
                    delta = choices[0].get("delta", {})
                    if not isinstance(delta, dict):
                        continue
                    part = delta.get("content")
                    if part:
                        yield str(part)
            return
        except Exception as exc:
            if not _should_fallback(exc):
                raise
            model = _fallback_model_name(model)

    payload = {
        "model": model,
        "messages": messages,
        "options": options or {},
        "stream": True,
    }
    with requests.post(OLLAMA_CHAT_URL, json=payload, timeout=timeout, stream=True) as response:
        response.raise_for_status()
        for raw_line in response.iter_lines(decode_unicode=True):
            if not raw_line:
                continue
            line = raw_line.strip()
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            part = obj.get("message", {}).get("content", "")
            if part:
                yield str(part)
            if obj.get("done"):
                break


def ensure_local_ollama_running() -> None:
    if get_provider() != "ollama":
        return

    try:
        subprocess.run(["ollama", "list"], check=True, capture_output=True, text=True)
    except Exception:
        env = os.environ.copy()
        env.setdefault("OLLAMA_HOST", "[::]:11434")
        subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
