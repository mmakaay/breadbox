"""
Integration tests that generate assembly and build it with ca65/ld65.

These tests verify that the generated assembly is syntactically valid
and produces a working ROM binary. They require ca65 and ld65 to be
available (in PATH or in ./cc65/bin/).
"""

import pytest
from pathlib import Path

from breadbox.builder import Builder, find_tool
from breadbox.config import BreadboxConfig
from breadbox.errors import BuildError
from breadbox.generator import CodeGenerator


def _ca65_available() -> bool:
    try:
        find_tool("ca65")
        return True
    except BuildError:
        return False


requires_ca65 = pytest.mark.skipif(
    not _ca65_available(),
    reason="ca65 not found (install cc65 or place in ./cc65/bin/)",
)


MINIMAL_CONFIG = """\
CORE:
  cpu: 65c02
  clock_mhz: 1.0
"""

MINIMAL_MAIN = """\
.include "breadbox.inc"

.export main

.proc main
    HALT
.endproc
"""

VIA_CONFIG = """\
CORE:
  cpu: 65c02
  clock_mhz: 1.0
VIA:
  component: via_w65c22
  address: $6000
"""


def _setup_project(project_dir: Path, config_yaml: str) -> tuple[Path, Path]:
    """
    Create a project with config and stub main.s, then generate.
    """
    (project_dir / "config.yaml").write_text(config_yaml)

    main_s = project_dir / "main.s"
    main_s.write_text(MINIMAL_MAIN)

    config = BreadboxConfig(project_dir)
    output_dir = project_dir / "generated" / "breadbox"
    generator = CodeGenerator(config, output_dir)
    generator.generate()

    return output_dir, main_s


@requires_ca65
class TestBuildMinimal:
    """
    Build a minimal CORE-only config into a ROM.
    """

    def test_produces_rom(self, tmp_path):
        output_dir, main_s = _setup_project(tmp_path, MINIMAL_CONFIG)
        builder = Builder(output_dir, tmp_path)
        rom_path = builder.build(extra_sources=[main_s])

        assert rom_path.exists()
        assert rom_path.stat().st_size > 0

    def test_rom_is_32k(self, tmp_path):
        """
        ROM binary should be 32KB (address space $8000-$FFFF).
        """
        output_dir, main_s = _setup_project(tmp_path, MINIMAL_CONFIG)
        builder = Builder(output_dir, tmp_path)
        rom_path = builder.build(extra_sources=[main_s])

        assert rom_path.stat().st_size == 32768

    def test_object_files_created(self, tmp_path):
        """
        Each .s file should produce a corresponding .o file.
        """
        output_dir, main_s = _setup_project(tmp_path, MINIMAL_CONFIG)
        builder = Builder(output_dir, tmp_path)
        builder.build(extra_sources=[main_s])

        assert (output_dir / "core" / "boot.o").exists()
        assert (output_dir / "core" / "vectors.o").exists()
        assert (output_dir / "core" / "delay.o").exists()
        assert (output_dir / "core" / "cpu_shims.o").exists()
        assert main_s.with_suffix(".o").exists()


@requires_ca65
class TestBuildWithVia:
    """
    Build a config with CORE + VIA into a ROM.
    """

    def test_via_config_builds(self, tmp_path):
        output_dir, main_s = _setup_project(tmp_path, VIA_CONFIG)
        builder = Builder(output_dir, tmp_path)
        rom_path = builder.build(extra_sources=[main_s])

        assert rom_path.exists()
        assert rom_path.stat().st_size == 32768


@requires_ca65
class TestBuild6502:
    """
    Build with plain 6502 CPU (not 65C02).
    """

    def test_6502_builds(self, tmp_path):
        config = """\
CORE:
  cpu: "6502"
  clock_mhz: 1.0
"""
        output_dir, main_s = _setup_project(tmp_path, config)
        builder = Builder(output_dir, tmp_path)
        rom_path = builder.build(extra_sources=[main_s])

        assert rom_path.exists()
        assert rom_path.stat().st_size == 32768


@requires_ca65
class TestAssemblyOnly:
    """
    Test that individual .s files assemble without errors.
    """

    def test_all_generated_s_files_assemble(self, tmp_path):
        output_dir, _ = _setup_project(tmp_path, MINIMAL_CONFIG)
        builder = Builder(output_dir, tmp_path)

        for s_file in sorted(output_dir.rglob("*.s")):
            o_file = builder._assemble(s_file)
            assert o_file.exists(), f"Failed to assemble {s_file.name}"


class TestFindTool:
    def test_nonexistent_tool_raises(self):
        with pytest.raises(BuildError, match="not found"):
            find_tool("nonexistent_tool_xyz_123")

    def test_finds_tool_or_skips(self):
        """
        find_tool either finds ca65 or raises BuildError.
        """
        try:
            path = find_tool("ca65")
            assert path.name == "ca65"
        except BuildError:
            pytest.skip("ca65 not available")
