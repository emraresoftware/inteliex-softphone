from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT_DIR / "data" / "islem_gunlugu.log"


class _Color:
    RESET = "\033[0m"
    GREY = "\033[90m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    CYAN = "\033[96m"


@dataclass(frozen=True)
class _LevelColor:
    level: int
    color: str


LEVEL_COLORS = [
    _LevelColor(logging.DEBUG, _Color.GREY),
    _LevelColor(logging.INFO, _Color.CYAN),
    _LevelColor(logging.WARNING, _Color.YELLOW),
    _LevelColor(logging.ERROR, _Color.RED),
    _LevelColor(logging.CRITICAL, _Color.RED),
]


class _ColorFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        base = super().format(record)
        color = _Color.GREEN
        for item in LEVEL_COLORS:
            if record.levelno == item.level:
                color = item.color
                break
        return f"{color}{base}{_Color.RESET}"


class DergahLogger:
    def __init__(self, name: str) -> None:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        self._logger = logging.getLogger(name)
        self._logger.setLevel(logging.INFO)
        self._logger.propagate = False
        if not self._logger.handlers:
            self._configure_handlers()

    def _configure_handlers(self) -> None:
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        console_handler.setFormatter(
            _ColorFormatter("%(asctime)s | %(name)s | %(levelname)s | %(message)s", "%Y-%m-%d %H:%M:%S")
        )

        file_handler = logging.FileHandler(LOG_PATH, encoding="utf-8")
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(
            logging.Formatter("%(asctime)s | %(name)s | %(levelname)s | %(message)s", "%Y-%m-%d %H:%M:%S")
        )

        self._logger.addHandler(console_handler)
        self._logger.addHandler(file_handler)

    def _emit(self, level: int, message: str, **context: object) -> None:
        if context:
            context_str = " | " + " ".join(f"{k}={v}" for k, v in context.items())
        else:
            context_str = ""
        self._logger.log(level, f"{message}{context_str}")

    def debug(self, message: str, **context: object) -> None:
        self._emit(logging.DEBUG, message, **context)

    def info(self, message: str, **context: object) -> None:
        self._emit(logging.INFO, message, **context)

    def warning(self, message: str, **context: object) -> None:
        self._emit(logging.WARNING, message, **context)

    def error(self, message: str, **context: object) -> None:
        self._emit(logging.ERROR, message, **context)

    def success(self, message: str, **context: object) -> None:
        self._emit(logging.INFO, f"SUCCESS: {message}", **context)


def get_logger(name: str) -> DergahLogger:
    return DergahLogger(name)
