from __future__ import annotations

"""
Dergah Goruntu Uretici — ComfyUI koprusu.

Ajanlar bu modulu kullanarak metin promptlarindan goruntu uretir.
ComfyUI REST API (varsayilan: 127.0.0.1:8188) uzerinden calisir.

Kullanim:
    # Komut satirindan
    python scripts/dervis_imager.py "bir dag manzarasi, gunes batimi"

    # Baska bir scriptten
    from dervis_imager import goruntu_uret
    sonuc = await goruntu_uret("bir dag manzarasi")
"""

import argparse
import asyncio
import json
import os
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import aiohttp

from logger import get_logger

ROOT_DIR = Path(__file__).resolve().parents[1]
LOGGER = get_logger("dervis_imager")

# --- Yapilandirma (env-var destekli) ---
COMFYUI_HOST = os.getenv("COMFYUI_HOST", "127.0.0.1")
COMFYUI_PORT = int(os.getenv("COMFYUI_PORT", "8188"))
COMFYUI_URL = f"http://{COMFYUI_HOST}:{COMFYUI_PORT}"

OUTPUT_DIR = ROOT_DIR / "data" / "goruntuler"
CHECKPOINT = os.getenv("COMFYUI_CHECKPOINT", "sd_xl_base_1.0.safetensors")

# Varsayilan uretim parametreleri
DEFAULT_WIDTH = int(os.getenv("COMFYUI_WIDTH", "1024"))
DEFAULT_HEIGHT = int(os.getenv("COMFYUI_HEIGHT", "1024"))
DEFAULT_STEPS = int(os.getenv("COMFYUI_STEPS", "20"))
DEFAULT_CFG = float(os.getenv("COMFYUI_CFG", "7.0"))
DEFAULT_SAMPLER = os.getenv("COMFYUI_SAMPLER", "euler")
DEFAULT_SCHEDULER = os.getenv("COMFYUI_SCHEDULER", "normal")

# Websocket bekleme suresi (saniye)
WS_TIMEOUT = int(os.getenv("COMFYUI_WS_TIMEOUT", "300"))


@dataclass
class ImagerResult:
    """Goruntu uretim sonucu."""
    ok: bool
    dosya: Path | None = None
    hata: str | None = None
    sure_sn: float = 0.0


def _sdxl_workflow(
    prompt: str,
    negative: str = "",
    seed: int | None = None,
    width: int = DEFAULT_WIDTH,
    height: int = DEFAULT_HEIGHT,
    steps: int = DEFAULT_STEPS,
    cfg: float = DEFAULT_CFG,
    sampler: str = DEFAULT_SAMPLER,
    scheduler: str = DEFAULT_SCHEDULER,
    upscale: float = 1.0,
) -> dict[str, Any]:
    """SDXL icin ComfyUI API workflow JSON'u olusturur."""
    if seed is None:
        seed = int.from_bytes(os.urandom(7), "big")

    workflow: dict[str, Any] = {
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["4", 0],
                "positive": ["6", 0],
                "negative": ["7", 0],
                "latent_image": ["5", 0],
                "seed": seed,
                "steps": steps,
                "cfg": cfg,
                "sampler_name": sampler,
                "scheduler": scheduler,
                "denoise": 1.0,
            },
        },
        "4": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": CHECKPOINT},
        },
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": width, "height": height, "batch_size": 1},
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": prompt, "clip": ["4", 1]},
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "text": negative or "bad quality, blurry, deformed",
                "clip": ["4", 1],
            },
        },
        "8": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["3", 0], "vae": ["4", 2]},
        },
    }

    # Upscale > 1 ise lanczos ile buyut, sonra kaydet
    if upscale > 1.0:
        workflow["10"] = {
            "class_type": "ImageScaleBy",
            "inputs": {
                "image": ["8", 0],
                "upscale_method": "lanczos",
                "scale_by": upscale,
            },
        }
        save_source = ["10", 0]
    else:
        save_source = ["8", 0]

    workflow["9"] = {
        "class_type": "SaveImage",
        "inputs": {"images": save_source, "filename_prefix": "dergah"},
    }

    return workflow


async def _comfyui_saglik() -> bool:
    """ComfyUI sunucusunun calisip calismadigini kontrol eder."""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{COMFYUI_URL}/system_stats", timeout=aiohttp.ClientTimeout(total=5)
            ) as resp:
                return resp.status == 200
    except Exception:
        return False


async def goruntu_uret(
    prompt: str,
    negative: str = "",
    seed: int | None = None,
    width: int = DEFAULT_WIDTH,
    height: int = DEFAULT_HEIGHT,
    steps: int = DEFAULT_STEPS,
    cfg: float = DEFAULT_CFG,
    sampler: str = DEFAULT_SAMPLER,
    scheduler: str = DEFAULT_SCHEDULER,
    upscale: float = 1.0,
) -> ImagerResult:
    """
    ComfyUI uzerinden goruntu uretir.

    Args:
        prompt: Pozitif metin promptu.
        negative: Negatif prompt (istenmeyen ozellikler).
        seed: Rastgele tohum (tekrarlanabilirlik icin).
        width: Goruntu genisligi (px).
        height: Goruntu yuksekligi (px).
        steps: Sampling adim sayisi.
        cfg: CFG olcegi.
        sampler: Sampler adi (euler, dpmpp_2m, vb.).
        scheduler: Scheduler adi (normal, karras, vb.).

    Returns:
        ImagerResult: ok=True ve dosya yolu, veya ok=False ve hata mesaji.
    """
    t0 = time.monotonic()
    LOGGER.info("Goruntu uretim basladi", prompt=prompt[:80], boyut=f"{width}x{height}")

    # ComfyUI canli mi?
    if not await _comfyui_saglik():
        return ImagerResult(ok=False, hata="ComfyUI sunucusu erisilemiyor")

    # Cikis klasorunu olustur
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    workflow = _sdxl_workflow(
        prompt=prompt,
        negative=negative,
        seed=seed,
        width=width,
        height=height,
        steps=steps,
        cfg=cfg,
        sampler=sampler,
        scheduler=scheduler,
        upscale=upscale,
    )

    client_id = uuid.uuid4().hex[:16]

    try:
        async with aiohttp.ClientSession() as session:
            # Prompt'u kuyruga ekle
            payload = {"prompt": workflow, "client_id": client_id}
            async with session.post(
                f"{COMFYUI_URL}/prompt", json=payload
            ) as resp:
                if resp.status != 200:
                    body = await resp.text()
                    return ImagerResult(ok=False, hata=f"Prompt reddedildi: {body[:200]}")
                data = await resp.json()
                prompt_id = data["prompt_id"]

            LOGGER.info("Kuyruga eklendi", prompt_id=prompt_id)

            # WebSocket ile tamamlanmayi bekle
            ws_url = f"ws://{COMFYUI_HOST}:{COMFYUI_PORT}/ws?clientId={client_id}"
            async with session.ws_connect(ws_url) as ws:
                async for msg in ws:
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        ws_data = json.loads(msg.data)
                        if ws_data.get("type") == "executing":
                            exec_data = ws_data.get("data", {})
                            if (
                                exec_data.get("prompt_id") == prompt_id
                                and exec_data.get("node") is None
                            ):
                                # Uretim tamamlandi
                                break
                    elif msg.type in (
                        aiohttp.WSMsgType.ERROR,
                        aiohttp.WSMsgType.CLOSED,
                    ):
                        return ImagerResult(
                            ok=False, hata="WebSocket baglantisi kesildi"
                        )

            # History'den dosya bilgisini al
            async with session.get(
                f"{COMFYUI_URL}/history/{prompt_id}"
            ) as resp:
                history = await resp.json()

            outputs = history.get(prompt_id, {}).get("outputs", {})
            # SaveImage node'unun (9) ciktisini bul
            save_node = outputs.get("9", {})
            images = save_node.get("images", [])
            if not images:
                return ImagerResult(ok=False, hata="Goruntu ciktisi bulunamadi")

            # Ilk goruntuyu indir
            img_info = images[0]
            img_params = {
                "filename": img_info["filename"],
                "subfolder": img_info.get("subfolder", ""),
                "type": img_info.get("type", "output"),
            }
            async with session.get(
                f"{COMFYUI_URL}/view", params=img_params
            ) as resp:
                if resp.status != 200:
                    return ImagerResult(
                        ok=False, hata="Goruntu indirilemedi"
                    )
                img_bytes = await resp.read()

            # Yerel dosyaya kaydet
            ts = time.strftime("%Y%m%d_%H%M%S")
            dosya_adi = f"dergah_{ts}_{uuid.uuid4().hex[:6]}.png"
            dosya_yolu = OUTPUT_DIR / dosya_adi
            dosya_yolu.write_bytes(img_bytes)

            sure = time.monotonic() - t0
            LOGGER.success(
                "Goruntu uretildi",
                dosya=str(dosya_yolu),
                sure_sn=f"{sure:.1f}",
                boyut_kb=f"{len(img_bytes) / 1024:.0f}",
            )
            return ImagerResult(ok=True, dosya=dosya_yolu, sure_sn=sure)

    except asyncio.TimeoutError:
        return ImagerResult(ok=False, hata=f"Zaman asimi ({WS_TIMEOUT}s)")
    except Exception as exc:
        LOGGER.error("Goruntu uretim hatasi", hata=str(exc))
        return ImagerResult(ok=False, hata=str(exc))


# --- Kolaylik fonksiyonlari (senkron sarmalayici) ---

def uret(prompt: str, **kwargs: Any) -> ImagerResult:
    """Senkron sarmalayici — async olmayan koddan cagirmak icin."""
    return asyncio.run(goruntu_uret(prompt, **kwargs))


# --- CLI giris noktasi ---

async def _main() -> None:
    parser = argparse.ArgumentParser(description="Dergah Goruntu Uretici")
    parser.add_argument("prompt", help="Goruntu promptu")
    parser.add_argument("--negative", default="", help="Negatif prompt")
    parser.add_argument("--width", type=int, default=DEFAULT_WIDTH)
    parser.add_argument("--height", type=int, default=DEFAULT_HEIGHT)
    parser.add_argument("--steps", type=int, default=DEFAULT_STEPS)
    parser.add_argument("--cfg", type=float, default=DEFAULT_CFG)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--sampler", default=DEFAULT_SAMPLER)
    parser.add_argument("--scheduler", default=DEFAULT_SCHEDULER)
    parser.add_argument("--upscale", type=float, default=1.0, help="Upscale carpani (2.0 = 2048x2048)")
    args = parser.parse_args()

    sonuc = await goruntu_uret(
        prompt=args.prompt,
        negative=args.negative,
        seed=args.seed,
        width=args.width,
        height=args.height,
        steps=args.steps,
        cfg=args.cfg,
        sampler=args.sampler,
        scheduler=args.scheduler,
        upscale=args.upscale,
    )

    if sonuc.ok:
        print(f"✅ Goruntu olusturuldu: {sonuc.dosya}  ({sonuc.sure_sn:.1f}s)")
    else:
        print(f"❌ Hata: {sonuc.hata}")


if __name__ == "__main__":
    asyncio.run(_main())
