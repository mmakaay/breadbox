from pathlib import Path

from breadbox.components.core.device import CoreDevice
from breadbox.components.ram.device import RamDevice
from breadbox.components.rom.device import RomDevice
from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.config import BreadboxConfig
from breadbox.generator import CodeGenerator, COMPONENTS_DIR, _hex_filter
from breadbox.memory import resolve_memory_layout
from breadbox.project import BreadboxProject
from breadbox.types.address16 import Address16
from breadbox.types.component_identifier import ComponentIdentifier
from breadbox.types.memory_size import MemorySize

CORE_ASSEMBLY_FILES = {
    "boot.s",
    "coding_macros.inc",
    "cpu_shims.s",
    "cpu_shims_macros.inc",
    "delay.s",
    "delay_macros.inc",
    "halt.s",
    "halt_macros.inc",
    "vectors.s",
    "vectors.inc",
    "api.inc",
}


def make_config():
    config = object.__new__(BreadboxConfig)
    config.components = {}
    config.memory_layout = None
    config.extra_source_dirs = []
    return config


def make_core_config(cpu="65c02", clock_mhz=1.0):
    config = make_config()
    core = CoreDevice(id=ComponentIdentifier("CORE"), cpu=cpu, clock_mhz=clock_mhz)
    config.components[ComponentIdentifier("CORE")] = core
    ram = RamDevice(id=ComponentIdentifier("RAM"), address=Address16("$0000"), size=MemorySize(0x4000))
    rom = RomDevice(id=ComponentIdentifier("ROM"), address=Address16("$8000"), size=MemorySize(0x8000))
    config.components[ram.id] = ram
    config.components[rom.id] = rom
    config.memory_layout = resolve_memory_layout([ram], [rom])
    return config


def make_core_via_config(cpu="65c02", clock_mhz=1.0, via_address="$6000"):
    config = make_core_config(cpu=cpu, clock_mhz=clock_mhz)
    via = ViaW65c22Device(id=ComponentIdentifier("VIA"), address=Address16(via_address))
    config.components[ComponentIdentifier("VIA")] = via
    return config


def make_project(tmp_path, config):
    """Build a BreadboxProject with pre-populated config, bypassing __init__."""
    project = object.__new__(BreadboxProject)
    project.config = config
    project.project_dir = tmp_path
    project.build_dir = tmp_path / "build"
    project.generated_dir = tmp_path / "build" / "breadbox"
    return project


def generate_from_yaml(tmp_path, config_yaml: str) -> BreadboxProject:
    config_path = tmp_path / "config.yaml"
    config_path.write_text(config_yaml)
    (tmp_path / "main.s").write_text('.include "breadbox.inc"\n.export main\n.proc main\n    HALT\n.endproc\n')

    project = BreadboxProject(config_path)
    generator = CodeGenerator(project)
    generator.generate()
    return project


class TestOutputDirectory:
    def test_creates_output_directory(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        generator = CodeGenerator(project)
        generator.generate()
        assert project.generated_dir.is_dir()

    def test_cleans_stale_files(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        output_dir.mkdir(parents=True)
        stale = output_dir / "stale.txt"
        stale.write_text("old content")

        project = make_project(tmp_path, make_core_config())
        generator = CodeGenerator(project)
        generator.generate()
        assert not stale.exists()

    def test_cleans_stale_subdirectories(self, tmp_path):
        output_dir = tmp_path / "build" / "breadbox"
        stale_dir = output_dir / "old_component"
        stale_dir.mkdir(parents=True)
        (stale_dir / "old.s").write_text("stale")

        project = make_project(tmp_path, make_core_config())
        generator = CodeGenerator(project)
        generator.generate()
        assert not stale_dir.exists()

    def test_empty_config_produces_base_files_only(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()
        files = {f.name for f in output_dir.iterdir() if f.is_file()}
        dirs = {d.name for d in output_dir.iterdir() if d.is_dir()}
        assert "breadbox.inc" in files
        assert "linker.cfg" in files
        assert "CORE" in dirs
        assert "stdlib" in dirs


class TestCoreGeneration:
    def test_creates_core_directory(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()
        assert (output_dir / "CORE").is_dir()

    def test_generates_all_assembly_files(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        actual_files = {f.name for f in (output_dir / "CORE").iterdir()}
        assert actual_files == CORE_ASSEMBLY_FILES

    def test_only_assembly_files_in_output(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        for f in (output_dir / "CORE").iterdir():
            assert f.suffix in (".s", ".inc"), f"Unexpected file: {f.name}"

    def test_s_files_match_source(self, tmp_path):
        """
        Assembly source files (.s) without template tags pass through unchanged.
        """
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        src_dir = COMPONENTS_DIR / "core" / "src"
        for src_file in src_dir.iterdir():
            if src_file.suffix == ".s" and "{{" not in src_file.read_text():
                generated = output_dir / "CORE" / src_file.name
                assert generated.read_text() == src_file.read_text(), f"Content mismatch for {src_file.name}"

    def test_inc_files_contain_source_content(self, tmp_path):
        """
        Include files have source content wrapped in auto-generated guards.
        """
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        src_dir = COMPONENTS_DIR / "core" / "src"
        for src_file in src_dir.iterdir():
            if src_file.suffix == ".inc" and "{{" not in src_file.read_text():
                generated = output_dir / "CORE" / src_file.name
                generated_content = generated.read_text()
                source_content = src_file.read_text().strip()
                assert source_content in generated_content, f"Source content missing from generated {src_file.name}"

    def test_delay_loop_handles_exact_256_multiples(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        generator = CodeGenerator(project)
        generator.generate()

        content = (project.generated_dir / "CORE" / "delay.s").read_text()
        assert "cpy #0" in content
        assert "@full_passes:" in content
        assert "inx" not in content

    def test_store16_parenthesizes_value_expression(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        generator = CodeGenerator(project)
        generator.generate()

        content = (project.generated_dir / "CORE" / "coding_macros.inc").read_text()
        assert "lda #<(_value)" in content
        assert "lda #>(_value)" in content


class TestIncludeGuards:
    def test_inc_files_have_auto_guards(self, tmp_path):
        """
        All generated .inc files have auto-generated include guards.
        """
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        for inc_file in (output_dir / "CORE").glob("*.inc"):
            content = inc_file.read_text()
            relative = inc_file.relative_to(output_dir)
            guard = "__" + str(relative).replace("/", "_").replace(".", "_").upper()
            assert content.startswith(f".ifndef {guard}\n{guard} = 1\n"), f"Missing guard in {inc_file.name}"
            assert content.rstrip().endswith(".endif"), f"Missing .endif in {inc_file.name}"

    def test_s_files_have_no_guards(self, tmp_path):
        """
        Assembly source files (.s) are not wrapped with include guards.
        """
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        for s_file in (output_dir / "CORE").glob("*.s"):
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
        result = CodeGenerator._wrap_include_guard("content", Path("some.inc"))
        assert result.startswith(".ifndef __SOME_INC\n__SOME_INC = 1\n")

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
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        content = (output_dir / "breadbox.inc").read_text()
        assert content.startswith(".ifndef __BREADBOX_INC\n__BREADBOX_INC = 1\n")


class TestBreadboxInc:
    def test_generates_breadbox_inc(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        assert (output_dir / "breadbox.inc").exists()

    def test_includes_core_files(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        content = (output_dir / "breadbox.inc").read_text()
        assert '.include "CORE/api.inc"' in content


class TestConsoleGeneration:
    def test_console_write_wraps_and_writes_via_row_pointer(self, tmp_path):
        project = generate_from_yaml(
            tmp_path,
            """\
CORE:
  cpu: 65c02
  clock_mhz: 1.0
VIA:
  component: via_w65c22
  address: $6000
LCD:
  component: lcd_hd44780
  width: 16
  height: 2
  cmnd_pins:
    provider: VIA
    rs_pin: PB0
    rwb_pin: PB1
    en_pin: PB2
  data_pins:
    provider: VIA
    mode: 4bit
    port: B
CONSOLE:
  provider: LCD
""",
        )

        content = (project.generated_dir / "CONSOLE" / "implementation.s").read_text()
        assert "cpy #15" in content
        assert "sta (__CONSOLE_row_ptr),y" in content
        assert "sta __CONSOLE_row_ptr,x" not in content
        assert "ldx __CONSOLE_cursor_column" in content
        assert "ldy __CONSOLE_cursor_row" in content
        assert "lda __CONSOLE_row_map,x" in content
        assert "txa" in content
        assert "ldx #0" in content
        assert "$6001" not in content


class TestViaGeneration:
    def test_generates_via_files(self, tmp_path):
        project = make_project(tmp_path, make_core_via_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        via_dir = output_dir / "VIA"
        assert via_dir.is_dir()
        assert (via_dir / "constants.inc").exists()
        assert (via_dir / "implementation.s").exists()

    def test_via_implementation_initializes_irq_state(self, tmp_path):
        project = make_project(tmp_path, make_core_via_config())
        generator = CodeGenerator(project)
        generator.generate()

        content = (project.generated_dir / "VIA" / "implementation.s").read_text()
        assert ".proc __VIA_init" in content
        assert "sta IER" in content
        assert "sta IFR" in content
        assert ".constructor __VIA_init" in content


class TestBreadboxCfg:
    def test_generates_linker_cfg(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        assert (output_dir / "linker.cfg").exists()

    def test_has_memory_section(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        content = (output_dir / "linker.cfg").read_text()
        assert "MEMORY {" in content

    def test_has_segments_section(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        content = (output_dir / "linker.cfg").read_text()
        assert "SEGMENTS {" in content

    def test_has_required_memory_regions(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        content = (output_dir / "linker.cfg").read_text()
        assert "ZEROPAGE:" in content
        assert "ROM:" in content
        assert "VECTORS:" in content

    def test_has_required_segments(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        content = (output_dir / "linker.cfg").read_text()
        assert "CODE:" in content
        assert "KERNALROM:" in content
        assert "VECTORS:" in content

    def test_no_include_guard(self, tmp_path):
        """
        Linker config files (.cfg) should not have include guards.
        """
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        content = (output_dir / "linker.cfg").read_text()
        assert ".ifndef" not in content

    def test_has_auto_generated_header(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        output_dir = project.generated_dir
        generator = CodeGenerator(project)
        generator.generate()

        content = (output_dir / "linker.cfg").read_text()
        assert "# Auto-generated by breadbox. Do not edit." in content

    def test_linker_cfg_has_condes_features(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        generator = CodeGenerator(project)
        generator.generate()

        content = (project.generated_dir / "linker.cfg").read_text()
        assert "CONDES: type = constructor" in content
        assert "CONDES: type = interruptor" in content
        assert "__CONSTRUCTOR_TABLE__" in content

    def test_linker_cfg_memory_addresses(self, tmp_path):
        project = make_project(tmp_path, make_core_config())
        generator = CodeGenerator(project)
        generator.generate()

        content = (project.generated_dir / "linker.cfg").read_text()
        assert "start = $0000" in content  # ZEROPAGE
        assert "start = $0100" in content  # STACK
        assert "start = $0200" in content  # RAM
        assert "start = $8000" in content  # ROM
        assert "start = $FFFA" in content  # VECTORS

    def test_project_linker_cfg_override(self, tmp_path):
        """
        A linker.cfg in the project directory overrides the generated one.
        It is processed as a Jinja2 template with the memory context.
        """
        project = make_project(tmp_path, make_core_config())
        custom_cfg = tmp_path / "linker.cfg"
        custom_cfg.write_text(
            "# Custom linker config\n{% for region in regions %}\nREGION: {{ region.name }}\n{% endfor %}\n"
        )
        generator = CodeGenerator(project)
        generator.generate()

        content = (project.generated_dir / "linker.cfg").read_text()
        assert "# Custom linker config" in content
        assert "REGION: ZEROPAGE" in content
        assert "REGION: ROM" in content


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
    def test_core_device_context(self, tmp_path):
        core = CoreDevice(id=ComponentIdentifier("CORE"), cpu="65c02", clock_mhz=1.0)
        generator = CodeGenerator(make_project(tmp_path, make_config()))
        context = generator._build_context(core)
        assert context["component_id"] == "CORE"
        assert context["component_type"] == "core"
        assert context["cpu"] == "65c02"
        assert context["clock_mhz"] == 1.0

    def test_excludes_internal_fields(self, tmp_path):
        core = CoreDevice(id=ComponentIdentifier("CORE"), cpu="65c02", clock_mhz=1.0)
        generator = CodeGenerator(make_project(tmp_path, make_config()))
        context = generator._build_context(core)
        assert "id" not in context
        assert "parent" not in context
