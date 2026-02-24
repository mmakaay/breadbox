from __future__ import annotations

import shutil
import subprocess
import sys
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

    Operates within a build directory containing:
    - breadbox/  (generated assembly: breadbox.cfg, core/*.s, etc.)
    - project/   (copied user source files)
    - rom.bin    (final output)
    """

    def __init__(self, build_dir: Path, *, verbose: bool = False) -> None:
        self.build_dir = build_dir
        self.generated_dir = build_dir / "breadbox"
        self.project_dir = build_dir / "project"
        self.verbose = verbose
        self.ca65 = find_tool("ca65")
        self.ld65 = find_tool("ld65")

    def _log(self, message: str) -> None:
        """
        Print a message to stderr when verbose mode is enabled.
        """
        if self.verbose:
            print(message, file=sys.stderr)

    def build(self, user_sources: list[Path] | None = None) -> Path:
        """
        Assemble all .s files and link into a ROM binary.

        User source files are copied into build/project/ before assembly.
        The resulting ROM is written to build/rom.bin.

        Args:
            user_sources: Additional .s files to include (e.g. user code).

        Returns:
            Path to the generated rom.bin.
        """
        object_files: list[Path] = []

        # Assemble all generated .s files.
        for s_file in sorted(self.generated_dir.rglob("*.s")):
            self._log(f"Assembling {s_file.relative_to(self.build_dir)}")
            object_files.append(self._assemble(s_file))

        # Copy and assemble user source files.
        if user_sources:
            self._prepare_project_dir()
            for src in user_sources:
                dest = self.project_dir / src.name
                shutil.copy2(src, dest)
                self._log(f"Assembling {dest.relative_to(self.build_dir)}")
                object_files.append(self._assemble(dest))

        # Link everything into a ROM binary.
        rom_path = self.build_dir / "rom.bin"
        self._log("Linking → rom.bin")
        self._link(object_files, rom_path)
        return rom_path

    def _prepare_project_dir(self) -> None:
        """
        Clean and recreate the project directory for user sources.
        """
        if self.project_dir.exists():
            shutil.rmtree(self.project_dir)
        self.project_dir.mkdir(parents=True)

    def _assemble(self, source: Path) -> Path:
        """
        Assemble a single .s file with ca65.
        """
        object_file = source.with_suffix(".o")
        result = subprocess.run(
            [str(self.ca65), "-I", str(self.generated_dir), str(source)],
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
        cfg_path = self.generated_dir / "breadbox.cfg"
        cmd = [str(self.ld65), "--config", str(cfg_path)]
        cmd.extend(str(o) for o in object_files)
        cmd.extend(["-o", str(rom_path)])
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise BuildError(f"Linking failed:\n{result.stderr}")
