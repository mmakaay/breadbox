from __future__ import annotations

import dataclasses
import shutil
from pathlib import Path
from typing import TYPE_CHECKING

from jinja2 import Environment, FileSystemLoader, StrictUndefined

if TYPE_CHECKING:
    from breadbox.config import BreadboxConfig
    from breadbox.types.device import Device

_COMPONENTS_DIR = Path(__file__).parent / "components"
_TEMPLATES_DIR = Path(__file__).parent / "templates"


def _hex_filter(value: int) -> str:
    """
    Format an integer as a ca65 hex literal ($XX or $XXXX).
    """
    if value <= 0xFF:
        return f"${value:02X}"
    return f"${value:04X}"


class CodeGenerator:
    """
    Walks the resolved device tree and generates ca65 assembly output.

    Implements the DeviceVisitor protocol to traverse the device hierarchy.
    Each component can ship assembly source files in a src/ directory alongside
    its Python code. The generator processes these through Jinja2 and writes
    the output to the target directory.

    All generated .inc files are automatically wrapped with .ifndef include
    guards derived from their output path (e.g. core/boot.inc -> __CORE_BOOT_INC).
    """

    def __init__(self, config: BreadboxConfig, output_dir: Path) -> None:
        self.config = config
        self.output_dir = output_dir
        self._template_env = self._create_template_env()

    def generate(self) -> None:
        """
        Generate all assembly output from the resolved config.
        """
        self._prepare_output_dir()
        for device in self.config.devices.values():
            if device.parent is None:
                device.accept(self)
        self._generate_hardware_inc()
        self._generate_breadbox_inc()
        self._generate_breadbox_cfg()

    def visit(self, device: Device) -> None:
        """
        Process a device and recurse into its sub-devices.
        """
        self._process_component_sources(device)
        for sub in device.devices:
            sub.accept(self)

    def _prepare_output_dir(self) -> None:
        """
        Clean and recreate the output directory.
        """
        if self.output_dir.exists():
            shutil.rmtree(self.output_dir)
        self.output_dir.mkdir(parents=True)

    def _create_template_env(self) -> Environment:
        """
        Create Jinja2 environment for top-level templates.
        """
        env = Environment(
            loader=FileSystemLoader(str(_TEMPLATES_DIR)),
            undefined=StrictUndefined,
            keep_trailing_newline=True,
            lstrip_blocks=True,
            trim_blocks=True,
        )
        env.filters["hex"] = _hex_filter
        return env

    def _generate_breadbox_inc(self) -> None:
        """
        Generate the master include file (breadbox.inc).

        This is the router that pulls in all generated includes.
        """
        template = self._template_env.get_template("breadbox.inc")
        rendered = template.render()
        self._write_output(Path("breadbox.inc"), rendered)

    def _generate_hardware_inc(self) -> None:
        """
        Generate hardware definitions (constants, macros) from device tree.
        """
        template = self._template_env.get_template("hardware.inc")
        rendered = template.render(devices=self.config.devices)
        self._write_output(Path("hardware.inc"), rendered)

    def _generate_breadbox_cfg(self) -> None:
        """
        Generate the ld65 linker configuration.
        """
        template = self._template_env.get_template("breadbox.cfg")
        rendered = template.render()
        self._write_output(Path("breadbox.cfg"), rendered)

    def _process_component_sources(self, device: Device) -> None:
        """
        Process a component's assembly source files into the output directory.

        Components that ship assembly source files in a src/ directory get those
        files rendered through Jinja2 and written to a matching subdirectory in
        the output (e.g. core/src/*.s -> generated/breadbox/core/*.s).
        """
        src_dir = _COMPONENTS_DIR / device.component_type / "src"
        if not src_dir.is_dir():
            return

        env = Environment(
            loader=FileSystemLoader(str(src_dir)),
            undefined=StrictUndefined,
            keep_trailing_newline=True,
            lstrip_blocks=True,
            trim_blocks=True,
        )

        context = self._build_context(device)

        for src_file in sorted(src_dir.iterdir()):
            if src_file.suffix in (".s", ".inc"):
                template = env.get_template(src_file.name)
                rendered = template.render(context)
                relative_path = Path(device.component_type) / src_file.name
                self._write_output(relative_path, rendered)

    def _write_output(self, relative_path: Path, content: str) -> None:
        """
        Write generated content to the output directory.

        For .inc files, automatically wraps content with .ifndef include guards
        derived from the output path.
        """
        if relative_path.suffix == ".inc":
            content = self._wrap_include_guard(content, relative_path)
        dest = self.output_dir / relative_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)

    @staticmethod
    def _wrap_include_guard(content: str, relative_path: Path) -> str:
        """
        Wrap content with .ifndef include guard.

        The guard symbol is derived from the relative output path with
        a __ prefix to avoid collisions with user-defined symbols:

            core/boot.inc -> __CORE_BOOT_INC
            hardware.inc  -> __HARDWARE_INC
        """
        guard = "__" + str(relative_path).replace("/", "_").replace(".", "_").upper()
        content = content.rstrip()
        return f".ifndef {guard}\n{guard} = 1\n\n{content}\n\n.endif\n"

    def _build_context(self, device: Device) -> dict:
        """
        Build the Jinja2 template context for a device.

        Includes device metadata and all public (non-internal) dataclass fields.
        """
        context: dict = {
            "device_id": str(device.id),
            "component_type": device.component_type,
        }
        for f in dataclasses.fields(device):
            if f.name not in device._internal_fields:
                context[f.name] = getattr(device, f.name)
        return context
