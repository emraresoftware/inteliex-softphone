"""Builder — manages file generation and project workspace."""

from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from chat import ChatEngine


class Builder:
    def __init__(self, workspace_dir: Path):
        self.workspace_dir = workspace_dir
        self.projects: dict[str, Path] = {}
        self.generated_files: dict[str, dict[str, str]] = {}  # session_id -> {path: code}

    def set_project(self, session_id: str, project_dir: Path):
        self.projects[session_id] = project_dir
        self.generated_files[session_id] = {}

    async def generate_file(
        self,
        session_id: str,
        file_path: str,
        file_description: str,
        full_plan: dict,
        chat_engine: "ChatEngine",
    ) -> str:
        project_dir = self.projects[session_id]

        # Pass already-generated files as context
        context_files = self.generated_files.get(session_id, {})

        code = await chat_engine.generate_code(
            file_path=file_path,
            file_description=file_description,
            plan=full_plan,
            context_files=context_files if context_files else None,
        )

        # Write file to disk
        target = project_dir / file_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(code, encoding="utf-8")

        # Track generated code for context in subsequent files
        self.generated_files.setdefault(session_id, {})[file_path] = code

        return code
