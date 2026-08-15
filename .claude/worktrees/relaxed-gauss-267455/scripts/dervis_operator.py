from __future__ import annotations

import asyncio
import os
import re
from pathlib import Path

from logger import get_logger
from llm_bridge import chat, get_default_model_name

MODEL_NAME = get_default_model_name()
ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_TIMEOUT_SECONDS = 240
COMMAND_PATTERN = re.compile(r"^KOMUT:\s*(.+)$", re.MULTILINE)

LOGGER = get_logger("dervis_operator")


def _extract_command(model_output: str) -> str | None:
    match = COMMAND_PATTERN.search(model_output)
    if not match:
        return None
    command = match.group(1).strip()
    if not command or command.lower() in {"none", "yok"}:
        return None
    return command


async def _run_command(command: str, cwd: Path) -> dict[str, str | int]:
    LOGGER.info("Komut calistiriliyor", command=command)
    process = await asyncio.create_subprocess_shell(
        command,
        cwd=str(cwd),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=os.environ.copy(),
    )
    try:
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=DEFAULT_TIMEOUT_SECONDS)
        return {
            "command": command,
            "returncode": process.returncode,
            "stdout": stdout.decode(errors="replace").strip(),
            "stderr": stderr.decode(errors="replace").strip(),
        }
    except asyncio.TimeoutError:
        process.kill()
        await process.communicate()
        return {
            "command": command,
            "returncode": -1,
            "stdout": "",
            "stderr": f"Komut {DEFAULT_TIMEOUT_SECONDS} saniyede zaman asimina ugradi",
        }


async def dervis_dongusu() -> None:
    LOGGER.success("Dervis Operator baslatildi", cwd=str(ROOT_DIR), model=MODEL_NAME)

    system_prompt = (
        "Sen bir terminal operatorusun. Sadece asagidaki formatta cevap ver:\n"
        "KOMUT: <terminal_komutu>\n"
        "GEREKCE: <kisa teknik aciklama>\n"
        "Komut disinda ek metin verme."
    )

    user_prompt = (
        f"Calisma dizini: {ROOT_DIR}. "
        "Amac: projects altindaki projeleri otonom yonetmek. Ilk komutu uret."
    )
    conversation = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt},
    ]

    while True:
        response = await asyncio.to_thread(
            chat,
            model=MODEL_NAME,
            messages=conversation,
        )
        model_output = response.get("message", {}).get("content", "")
        LOGGER.info("Model yaniti alindi", response=model_output)

        command = _extract_command(model_output)
        if not command:
            LOGGER.warning("Model KOMUT formati disinda yanit verdi")
            conversation.append(
                {
                    "role": "user",
                    "content": "Yanit gecersizdi. Lutfen yalnizca KOMUT formatinda cevap ver.",
                }
            )
            continue

        if command.lower() in {"exit", "quit", "stop"}:
            LOGGER.success("Model donguyu sonlandirmayi istedi")
            break

        result = await _run_command(command, ROOT_DIR)
        LOGGER.success("Komut tamamlandi", returncode=result["returncode"])  # type: ignore[index]
        result_message = (
            f"Komut: {result['command']}\n"
            f"Cikis Kodu: {result['returncode']}\n"
            f"STDOUT:\n{result['stdout'] or '<bos>'}\n"
            f"STDERR:\n{result['stderr'] or '<bos>'}\n"
            "Sonraki adim icin yeni KOMUT uret."
        )
        conversation.extend(
            [
                {"role": "assistant", "content": model_output},
                {"role": "user", "content": result_message},
            ]
        )


if __name__ == "__main__":
    asyncio.run(dervis_dongusu())