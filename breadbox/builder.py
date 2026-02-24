from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from breadbox.errors import BuildError


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

    Expects the output directory to contain:
    - breadbox.cfg (linker configuration)
    - core/*.s (core assembly source files)
    - Any other generated .s files

    Optionally accepts extra source files (e.g. user's project.s)
    to include in the build.
    """

    def __init__(self, output_dir: Path, project_dir: Path) -> None:
        self.output_dir = output_dir
        self.project_dir = project_dir
        self.ca65 = find_tool("ca65")
        self.ld65 = find_tool("ld65")

    def build(self, extra_sources: list[Path] | None = None) -> Path:
        """
        Assemble all .s files and link into a ROM binary.

        Args:
            extra_sources: Additional .s files to assemble (e.g. user code).

        Returns:
            Path to the generated rom.bin.
        """
        object_files: list[Path] = []

        # Assemble all generated .s files.
        for s_file in sorted(self.output_dir.rglob("*.s")):
            object_files.append(self._assemble(s_file))

        # Assemble extra source files.
        for s_file in extra_sources or []:
            object_files.append(self._assemble(s_file))

        # Link everything into a ROM binary.
        rom_path = self.project_dir / "rom.bin"
        self._link(object_files, rom_path)
        return rom_path

    def _assemble(self, source: Path) -> Path:
        """
        Assemble a single .s file with ca65.
        """
        object_file = source.with_suffix(".o")
        result = subprocess.run(
            [str(self.ca65), "-I", str(self.output_dir), str(source)],
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
        cfg_path = self.output_dir / "breadbox.cfg"
        cmd = [str(self.ld65), "--config", str(cfg_path)]
        cmd.extend(str(o) for o in object_files)
        cmd.extend(["-o", str(rom_path)])
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise BuildError(f"Linking failed:\n{result.stderr}")
