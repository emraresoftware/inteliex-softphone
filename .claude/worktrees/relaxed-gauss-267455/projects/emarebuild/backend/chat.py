"""Chat engine — LLM integration for planning and code generation."""

import json
import re
from typing import Any, Optional

import httpx

from config import OLLAMA_URL, MODEL

MAX_RETRIES = 2

SYSTEM_PROMPT = """Sen bir web uygulaması geliştirici asistanısın. Kullanıcı sana ne tür bir uygulama istediğini anlatacak.

Görevin:
1. Kullanıcının isteğini anla
2. Hangi dosyaların oluşturulması gerektiğini planla
3. Her dosyanın içeriğini yaz

KURALLAR:
- Sadece HTML, CSS ve JavaScript kullan (vanilla, framework yok)
- Modern, responsive tasarım yap
- Türkçe arayüz
- index.html ana dosya olsun
- CSS'i style.css dosyasına koy
- JavaScript'i app.js dosyasına koy
- Temiz, okunabilir kod yaz"""

PLAN_PROMPT = """Kullanıcı şu uygulamayı istiyor:

"{user_message}"

Lütfen bir plan oluştur. Yanıtını SADECE şu JSON formatında ver, başka bir şey yazma:

{{
  "explanation": "Kullanıcıya Türkçe açıklama (ne yapılacak, kısa)",
  "files": [
    {{"path": "index.html", "description": "Ana sayfa"}},
    {{"path": "style.css", "description": "Stil dosyası"}},
    {{"path": "app.js", "description": "Uygulama mantığı"}}
  ]
}}

Dosya listesini uygulamaya göre ayarla. Gerekirse ek dosya ekle."""

CODE_PROMPT = """Şu uygulama planının bir parçası olarak "{file_path}" dosyasını yaz.

Uygulama açıklaması: {explanation}

Plan dosyaları: {files_list}

Dosya açıklaması: {file_description}

{context}

SADECE dosya içeriğini yaz, açıklama veya markdown code block ekleme. Düz kod yaz."""


class ChatEngine:
    def __init__(self):
        self.sessions: dict[str, list[dict]] = {}

    def _get_history(self, session_id: str) -> list[dict]:
        if session_id not in self.sessions:
            self.sessions[session_id] = []
        return self.sessions[session_id]

    async def _call_llm(self, messages: list[dict], temperature: float = 0.3) -> str:
        async with httpx.AsyncClient(timeout=120) as client:
            resp = await client.post(
                f"{OLLAMA_URL}/api/chat",
                json={
                    "model": MODEL,
                    "messages": messages,
                    "stream": True,
                    "options": {
                        "temperature": temperature,
                        "num_ctx": 16384,
                    },
                },
            )
            resp.raise_for_status()
            async for chunk in resp.aiter_text():
                yield chunk

    def _extract_json(self, text: str) -> dict:
        """Extract JSON from LLM response, handling markdown code blocks."""
        # Try to find JSON in code blocks
        match = re.search(r"```(?:json)?\s*\n?(.*?)\n?```", text, re.DOTALL)
        if match:
            text = match.group(1)

        # Try to find raw JSON object
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                pass

        # Fallback plan
        return {
            "explanation": "Uygulamanızı oluşturuyorum...",
            "files": [
                {"path": "index.html", "description": "Ana sayfa"},
                {"path": "style.css", "description": "Stiller"},
                {"path": "app.js", "description": "Uygulama mantığı"},
            ],
        }

    async def plan_app(self, user_message: str, session_id: str) -> dict:
        history = self._get_history(session_id)
        history.append({"role": "user", "content": user_message})

        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": PLAN_PROMPT.format(user_message=user_message)},
        ]

        raw = await self._call_llm(messages, temperature=0.3)
        plan = self._extract_json(raw)

        history.append({"role": "assistant", "content": json.dumps(plan, ensure_ascii=False)})
        plan["_user_message"] = user_message
        return plan

    async def generate_code(
        self,
        file_path: str,
        file_description: str,
        plan: dict,
        context_files: Optional[dict[str, str]] = None,
    ) -> str:
        files_list = ", ".join(f["path"] for f in plan.get("files", []))

        context = ""
        if context_files:
            parts = []
            for name, code in context_files.items():
                parts.append(f"--- {name} ---\n{code}")
            context = "Daha önce oluşturulan dosyalar:\n\n" + "\n\n".join(parts)

        prompt = CODE_PROMPT.format(
            file_path=file_path,
            explanation=plan.get("explanation", plan.get("_user_message", "")),
            files_list=files_list,
            file_description=file_description,
            context=context,
        )

        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ]

        for attempt in range(MAX_RETRIES + 1):
            try:
                raw = await self._call_llm(messages, temperature=0.2)

                # Strip markdown code fences if present
                raw = raw.strip()
                if raw.startswith("``"):
                    lines = raw.split("\n")
                    lines = lines[1:]  # remove opening fence
                    if lines and lines[-1].strip() == "```":
                        lines = lines[:-1]
                    raw = "\n".join(lines)

                return raw
            except Exception as e:
                if attempt < MAX_RETRIES:
                    print(f"Attempt {attempt + 1} failed: {e}. Retrying...")
                else:
                    raise

        # Fallback plan if all retries fail
        return "Uygulama oluşturulamadı. Lütfen tekrar deneyin."