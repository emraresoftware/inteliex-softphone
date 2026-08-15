"""EmareBuild — AI-powered app builder backend."""

import asyncio
import json
import os
import uuid
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles

from builder import Builder
from chat import ChatEngine

BASE_DIR = Path(__file__).resolve().parent.parent
FRONTEND_DIR = BASE_DIR / "frontend"
WORKSPACE_DIR = BASE_DIR / "workspace"

app = FastAPI(title="EmareBuild")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve generated project files for preview
app.mount("/preview", StaticFiles(directory=str(WORKSPACE_DIR), html=True), name="preview")
app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR)), name="static")

chat_engine = ChatEngine()
builder = Builder(workspace_dir=WORKSPACE_DIR)


@app.get("/")
async def index():
    return FileResponse(FRONTEND_DIR / "index.html")


@app.get("/api/health")
async def health():
    return {"status": "ok"}


@app.websocket("/ws/{session_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: str):
    await websocket.accept()

    # Initialize session workspace
    project_dir = WORKSPACE_DIR / session_id
    project_dir.mkdir(parents=True, exist_ok=True)
    builder.set_project(session_id, project_dir)

    # Send greeting
    await websocket.send_json({
        "type": "assistant",
        "content": "Merhaba! Ben EmareBuild asistanınız. 🚀\n\nHangi tür bir uygulama yapmak istiyorsunuz? Bana anlatın, hemen kodlamaya başlayalım.",
    })

    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type", "chat")

            if msg_type == "chat":
                user_message = data.get("content", "").strip()
                if not user_message:
                    continue

                # Step 1: AI acknowledges and plans
                await websocket.send_json({
                    "type": "status",
                    "content": "Düşünüyorum...",
                })

                try:
                    # Step 2: Generate plan via LLM
                    plan = await chat_engine.plan_app(user_message, session_id)

                    await websocket.send_json({
                        "type": "assistant",
                        "content": plan["explanation"],
                    })

                    await websocket.send_json({
                        "type": "status",
                        "content": "Kod yazılıyor...",
                    })

                    # Step 3: Generate files one by one
                    files = plan.get("files", [])
                    for file_info in files:
                        filename = file_info["path"]
                        await websocket.send_json({
                            "type": "building",
                            "file": filename,
                            "content": f"📝 {filename} oluşturuluyor...",
                        })

                        code = await builder.generate_file(
                            session_id=session_id,
                            file_path=filename,
                            file_description=file_info.get("description", ""),
                            full_plan=plan,
                            chat_engine=chat_engine,
                        )

                        await websocket.send_json({
                            "type": "file_created",
                            "file": filename,
                            "code": code,
                        })

                    # Step 4: Signal preview is ready
                    await websocket.send_json({
                        "type": "preview_ready",
                        "url": f"/preview/{session_id}/index.html",
                    })

                    await websocket.send_json({
                        "type": "assistant",
                        "content": "✅ Uygulamanız hazır! Sağ panelde önizlemeyi görebilirsiniz.\n\nDeğişiklik yapmak ister misiniz?",
                    })

                except Exception as e:
                    await websocket.send_json({
                        "type": "error",
                        "content": f"Ollama bağlantısı sırasında bir hata oluştu: {str(e)}"
                    })

    except WebSocketDisconnect:
        pass