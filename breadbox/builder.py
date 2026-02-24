from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

from rich.console import Console

from breadbox.errors import BuildError

console = Console()

if TYPE_CHECKING:
    from breadbox.project import BreadboxProject


def find_tool(name: str) -> Path:
    """
    Find a cc65 tool binary.

    Looks in PATH first, then falls back to ./cc65/bin/ relative to CWD.
    """
    found = shutil.which(name)
    if found:
        return Path(found)

    fallback = Path("cc65") / "bin" / name
    if fallback.is_file():
        return fallback

    raise BuildError(f"'{name}' not found. Install cc65 to your PATH or place it in ./cc65/bin/")


class Builder:
    """
    Assembles and links generated ca65 assembly into a ROM binary.

    Discovers user .s files from the project directory, copies them
    into build/project/, assembles everything alongside generated
    assembly, and links into build/rom.bin.
    """

    def __init__(self, project: BreadboxProject, *, verbose: bool = False) -> None:
        self.project = project
        self._user_dir = project.build_dir / "project"
        self.verbose = verbose
        self.ca65 = find_tool("ca65")
        self.ld65 = find_tool("ld65")

    def _log(self, message: str) -> None:
        """
        Print a log message when verbose mode is enabled.
        """
        if self.verbose:
            console.print(message)

    def build(self) -> Path:
        """
        Assemble all .s files and link into a ROM binary.

        Discovers user .s files from the project directory, copies them
        into build/project/, assembles everything, and links into
        build/rom.bin.

        Returns:
            Path to the generated rom.bin.
        """
        object_files: list[Path] = []

        # Assemble all generated .s files.
        for s_file in sorted(self.project.generated_dir.rglob("*.s")):
            self._log(f"  Assembling {s_file.relative_to(self.project.build_dir)}")
            object_files.append(self._assemble(s_file))

        # Discover, copy, and assemble user source files.
        user_sources = sorted(self.project.project_dir.glob("*.s"))
        if user_sources:
            self._prepare_user_dir()
            for src in user_sources:
                dest = self._user_dir / src.name
                shutil.copy2(src, dest)
                self._log(f"  Assembling {dest.relative_to(self.project.build_dir)}")
                object_files.append(self._assemble(dest))

        # Link everything into a ROM binary.
        rom_path = self.project.build_dir / "rom.bin"
        self._log("[green]Link object files \u2192 rom.bin[/green]")
        self._link(object_files, rom_path)
        return rom_path

    def _prepare_user_dir(self) -> None:
        """
        Clean and recreate the directory for user sources.
        """
        if self._user_dir.exists():
            shutil.rmtree(self._user_dir)
        self._user_dir.mkdir(parents=True)

    def _assemble(self, source: Path) -> Path:
        """
        Assemble a single .s file with ca65.
        """
        object_file = source.with_suffix(".o")
        result = subprocess.run(
            [str(self.ca65), "-I", str(self.project.generated_dir), str(source)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise BuildError(f"Assembly failed for {source.name}:\n{result.stderr}")
        return object_file

    def _link(self, object_files: list[Path], rom_path: Path) -> None:
        """
        Link object files into a ROM binary with ld65.
        """
        cfg_path = self.project.generated_dir / "breadbox.cfg"
        cmd = [str(self.ld65), "--config", str(cfg_path)]
        cmd.extend(str(o) for o in object_files)
        cmd.extend(["-o", str(rom_path)])
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise BuildError(f"Linking failed:\n{result.stderr}")
