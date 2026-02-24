import pytest
from pathlib import Path

from breadbox.components.core.device import CoreDevice
from breadbox.components.via_w65c22.device import ViaW65c22Device, REGISTERS
from breadbox.config import BreadboxConfig
from breadbox.generator import CodeGenerator, _COMPONENTS_DIR, _hex_filter
from breadbox.types.address16 import Address16
from breadbox.types.device_identifier import DeviceIdentifier


CORE_ASSEMBLY_FILES = {
    "boot.s",
    "boot.inc",
    "vectors.s",
    "vectors.inc",
    "delay.s",
    "delay.inc",
    "cpu_shims.s",
    "cpu_shims.inc",
}


def make_config():
    config = object.__new__(BreadboxConfig)
    config.devices = {}
    return config


def make_core_config(cpu="65c02", clock_mhz=1.0):
    config = make_config()
    core = CoreDevice(id=DeviceIdentifier("CORE"), cpu=cpu, clock_mhz=clock_mhz)
    config.devices[DeviceIdentifier("CORE")] = core
    return config


def make_core_via_config(cpu="65c02", clock_mhz=1.0, via_address="$6000"):
    config = make_core_config(cpu=cpu, clock_mhz=clock_mhz)
    via = ViaW65c22Device(id=DeviceIdentifier("VIA"), address=Address16(via_address))
    config.devices[DeviceIdentifier("VIA")] = via
    return config


class TestOutputDirectory:
    def test_creates_output_directory(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_config(), output_dir)
        generator.generate()
        assert output_dir.is_dir()

    def test_cleans_stale_files(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        output_dir.mkdir(parents=True)
        stale = output_dir / "stale.txt"
        stale.write_text("old content")

        generator = CodeGenerator(make_config(), output_dir)
        generator.generate()
        assert not stale.exists()

    def test_cleans_stale_subdirectories(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        stale_dir = output_dir / "old_component"
        stale_dir.mkdir(parents=True)
        (stale_dir / "old.s").write_text("stale")

        generator = CodeGenerator(make_config(), output_dir)
        generator.generate()
        assert not stale_dir.exists()

    def test_empty_config_produces_base_files_only(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_config(), output_dir)
        generator.generate()
        files = {f.name for f in output_dir.iterdir() if f.is_file()}
        dirs = {d.name for d in output_dir.iterdir() if d.is_dir()}
        assert files == {"breadbox.inc", "hardware.inc", "breadbox.cfg"}
        assert dirs == set()


class TestCoreGeneration:
    def test_creates_core_directory(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()
        assert (output_dir / "core").is_dir()

    def test_generates_all_assembly_files(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        actual_files = {f.name for f in (output_dir / "core").iterdir()}
        assert actual_files == CORE_ASSEMBLY_FILES

    def test_only_assembly_files_in_output(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        for f in (output_dir / "core").iterdir():
            assert f.suffix in (".s", ".inc"), f"Unexpected file: {f.name}"

    def test_s_files_match_source(self, tmp_path):
        """
        Assembly source files (.s) pass through unchanged.
        """
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        src_dir = _COMPONENTS_DIR / "core" / "src"
        for src_file in src_dir.iterdir():
            if src_file.suffix == ".s":
                generated = output_dir / "core" / src_file.name
                assert generated.read_text() == src_file.read_text(), f"Content mismatch for {src_file.name}"

    def test_inc_files_contain_source_content(self, tmp_path):
        """
        Include files have source content wrapped in auto-generated guards.
        """
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        src_dir = _COMPONENTS_DIR / "core" / "src"
        for src_file in src_dir.iterdir():
            if src_file.suffix == ".inc":
                generated = output_dir / "core" / src_file.name
                generated_content = generated.read_text()
                source_content = src_file.read_text().strip()
                assert source_content in generated_content, f"Source content missing from generated {src_file.name}"


class TestIncludeGuards:
    def test_inc_files_have_auto_guards(self, tmp_path):
        """
        All generated .inc files have auto-generated include guards.
        """
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        for inc_file in (output_dir / "core").glob("*.inc"):
            content = inc_file.read_text()
            relative = inc_file.relative_to(output_dir)
            guard = "__" + str(relative).replace("/", "_").replace(".", "_").upper()
            assert content.startswith(f".ifndef {guard}\n{guard} = 1\n"), f"Missing guard in {inc_file.name}"
            assert content.rstrip().endswith(".endif"), f"Missing .endif in {inc_file.name}"

    def test_s_files_have_no_guards(self, tmp_path):
        """
        Assembly source files (.s) are not wrapped with include guards.
        """
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        for s_file in (output_dir / "core").glob("*.s"):
            content = s_file.read_text()
            assert not content.startswith(".ifndef"), f"Unexpected guard in {s_file.name}"

    def test_guard_symbol_from_path(self):
        """
        Guard symbol is derived from relative output path with __ prefix.
        """
        result = CodeGenerator._wrap_include_guard("content", Path("core/boot.inc"))
        assert result.startswith(".ifndef __CORE_BOOT_INC\n__CORE_BOOT_INC = 1\n")

    def test_guard_symbol_for_top_level(self):
        """
        Top-level .inc files get guard from filename only.
        """
        result = CodeGenerator._wrap_include_guard("content", Path("hardware.inc"))
        assert result.startswith(".ifndef __HARDWARE_INC\n__HARDWARE_INC = 1\n")

    def test_guard_wraps_content(self):
        """
        Guard wraps content between header and .endif.
        """
        result = CodeGenerator._wrap_include_guard("hello\nworld\n", Path("test.inc"))
        lines = result.split("\n")
        assert lines[0] == ".ifndef __TEST_INC"
        assert lines[1] == "__TEST_INC = 1"
        assert lines[2] == ""
        assert "hello" in result
        assert "world" in result
        assert lines[-2] == ".endif"

    def test_guard_strips_trailing_whitespace(self):
        """
        Trailing whitespace in content is cleaned before wrapping.
        """
        result = CodeGenerator._wrap_include_guard("content\n\n\n", Path("test.inc"))
        # Should have exactly: guard header, blank, content, blank, .endif
        assert "\n\ncontent\n\n.endif\n" in result

    def test_breadbox_inc_has_guard(self, tmp_path):
        """
        The master include file gets its own guard.
        """
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "breadbox.inc").read_text()
        assert content.startswith(".ifndef __BREADBOX_INC\n__BREADBOX_INC = 1\n")

    def test_hardware_inc_has_guard(self, tmp_path):
        """
        The hardware definitions file gets its own guard.
        """
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        assert content.startswith(".ifndef __HARDWARE_INC\n__HARDWARE_INC = 1\n")


class TestBreadboxInc:
    def test_generates_breadbox_inc(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        assert (output_dir / "breadbox.inc").exists()

    def test_includes_hardware(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "breadbox.inc").read_text()
        assert '.include "hardware.inc"' in content

    def test_includes_core_files(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "breadbox.inc").read_text()
        assert '.include "core/cpu_shims.inc"' in content
        assert '.include "core/delay.inc"' in content
        assert '.include "core/boot.inc"' in content
        assert '.include "core/vectors.inc"' in content

    def test_hardware_included_before_core(self, tmp_path):
        """
        hardware.inc must be included before core files (defines CPU_CLOCK etc.).
        """
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "breadbox.inc").read_text()
        hw_pos = content.index('.include "hardware.inc"')
        core_pos = content.index('.include "core/boot.inc"')
        assert hw_pos < core_pos


class TestHardwareInc:
    def test_generates_hardware_inc(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_via_config(), output_dir)
        generator.generate()

        assert (output_dir / "hardware.inc").exists()

    def test_core_setcpu(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_via_config(), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        assert '.setcpu "65c02"' in content

    def test_core_setcpu_6502(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_via_config(cpu="6502"), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        assert '.setcpu "6502"' in content

    def test_core_clock(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_via_config(), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        assert "CPU_CLOCK = 1000000" in content

    def test_core_clock_4mhz(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_via_config(clock_mhz=4.0), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        assert "CPU_CLOCK = 4000000" in content

    def test_via_base_address(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_via_config(), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        assert "VIA_BASE = $6000" in content

    def test_via_base_address_custom(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_via_config(via_address="$7000"), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        assert "VIA_BASE = $7000" in content

    def test_via_registers(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_via_config(), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        assert "VIA_PORTB = VIA_BASE + $00" in content
        assert "VIA_PORTA = VIA_BASE + $01" in content
        assert "VIA_DDRB = VIA_BASE + $02" in content
        assert "VIA_DDRA = VIA_BASE + $03" in content
        assert "VIA_IER = VIA_BASE + $0E" in content
        assert "VIA_PORTA_NH = VIA_BASE + $0F" in content

    def test_via_all_sixteen_registers(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_via_config(), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        for name, offset in REGISTERS:
            expected = f"VIA_{name} = VIA_BASE + ${offset:02X}"
            assert expected in content, f"Missing register: {expected}"

    def test_empty_config_hardware_inc(self, tmp_path):
        """
        Empty config produces hardware.inc with header only.
        """
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_config(), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        assert ".ifndef __HARDWARE_INC" in content
        assert ".setcpu" not in content
        assert "BASE" not in content

    def test_has_auto_generated_header(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_via_config(), output_dir)
        generator.generate()

        content = (output_dir / "hardware.inc").read_text()
        assert "; Auto-generated by breadbox. Do not edit." in content


class TestBreadboxCfg:
    def test_generates_breadbox_cfg(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        assert (output_dir / "breadbox.cfg").exists()

    def test_has_memory_section(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "breadbox.cfg").read_text()
        assert "MEMORY {" in content

    def test_has_segments_section(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "breadbox.cfg").read_text()
        assert "SEGMENTS {" in content

    def test_has_required_memory_regions(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "breadbox.cfg").read_text()
        assert "ZEROPAGE:" in content
        assert "ROM:" in content
        assert "VECTORS:" in content

    def test_has_required_segments(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "breadbox.cfg").read_text()
        assert "CODE:" in content
        assert "KERNAL:" in content
        assert "VECTORS:" in content

    def test_no_include_guard(self, tmp_path):
        """
        Linker config files (.cfg) should not have include guards.
        """
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "breadbox.cfg").read_text()
        assert ".ifndef" not in content

    def test_has_auto_generated_header(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        generator = CodeGenerator(make_core_config(), output_dir)
        generator.generate()

        content = (output_dir / "breadbox.cfg").read_text()
        assert "# Auto-generated by breadbox. Do not edit." in content


class TestHexFilter:
    def test_single_byte(self):
        assert _hex_filter(0x00) == "$00"
        assert _hex_filter(0x0F) == "$0F"
        assert _hex_filter(0xFF) == "$FF"

    def test_two_bytes(self):
        assert _hex_filter(0x100) == "$0100"
        assert _hex_filter(0x6000) == "$6000"
        assert _hex_filter(0xFFFF) == "$FFFF"

    def test_uppercase(self):
        assert _hex_filter(0x0A) == "$0A"
        assert _hex_filter(0xABCD) == "$ABCD"


class TestBuildContext:
    def test_core_device_context(self):
        core = CoreDevice(id=DeviceIdentifier("CORE"), cpu="65c02", clock_mhz=1.0)
        generator = CodeGenerator(make_config(), Path("/unused"))
        context = generator._build_context(core)
        assert context["device_id"] == "CORE"
        assert context["component_type"] == "core"
        assert context["cpu"] == "65c02"
        assert context["clock_mhz"] == 1.0

    def test_excludes_internal_fields(self):
        core = CoreDevice(id=DeviceIdentifier("CORE"), cpu="65c02", clock_mhz=1.0)
        generator = CodeGenerator(make_config(), Path("/unused"))
        context = generator._build_context(core)
        assert "id" not in context
        assert "parent" not in context
