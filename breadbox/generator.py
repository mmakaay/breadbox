from __future__ import annotations

import dataclasses
import shutil
from functools import cached_property
from pathlib import Path
from typing import TYPE_CHECKING

from jinja2 import Environment, FileSystemLoader, StrictUndefined

from breadbox.errors import ConfigError
from breadbox.visitors.bus_client_collector import BusClientCollector

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
        self._bus_collector = BusClientCollector()
        self._device_includes: list[Path] = []

    def generate(self) -> None:
        """
        Generate all assembly output from the resolved config.
        """
        self._prepare_output_dir()
        self._collect_bus_clients()
        self._validate_bus_clients()
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

    def _collect_bus_clients(self) -> None:
        """
        Walk the full device tree and register bus clients.

        Must run before code generation so that bus devices
        can answer queries about their clients (e.g. port exclusivity).
        """
        for device in self.config.devices.values():
            if device.parent is None:
                device.accept(self._bus_collector)

    def _validate_bus_clients(self) -> None:
        """
        Ask each device to validate its registered bus clients.

        Wraps any ValueError from device validation as ConfigError
        so the CLI can display it cleanly without a stack trace.
        """
        for device in self.config.devices.values():
            try:
                device.validate_bus_clients()
            except ValueError as e:
                raise ConfigError(str(e)) from None

    def _prepare_output_dir(self) -> None:
        """
        Clean and recreate the output directory.
        """
        if self.output_dir.exists():
            shutil.rmtree(self.output_dir)
        self.output_dir.mkdir(parents=True)
        # Tag the build root as a cache directory for backup tools.
        (self.output_dir.parent / "CACHEDIR.TAG").write_text(
            "Signature: 8a477f597d28d172789f06886806bc55\n"
            "# This directory is managed by breadbox and can be safely regenerated.\n"
        )

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

        Pulls in hardware definitions, core assembly, and all
        device-generated include files.
        """
        template = self._template_env.get_template("breadbox.inc")
        rendered = template.render(device_includes=self._device_includes)
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

        Uses the device's component_dir (via inspect) to locate the src/
        directory. Output files are placed under the device's build_dir,
        which mirrors the device tree (e.g. the_display/pin_rs/).
        """
        src_dir = device.component_dir / "src"
        if not src_dir.is_dir():
            return

        env = Environment(
            loader=FileSystemLoader(str(src_dir)),
            undefined=StrictUndefined,
            keep_trailing_newline=True,
            lstrip_blocks=True,
            trim_blocks=True,
        )
        env.filters["hex"] = _hex_filter

        context = self._build_context(device)

        src_files = sorted(f for f in src_dir.iterdir() if f.suffix in (".s", ".inc"))
        for src_file in src_files:
            template = env.get_template(src_file.name)
            rendered = template.render(context)
            relative_path = Path(device.build_dir) / src_file.name
            self._write_output(relative_path, rendered)
            if relative_path.suffix == ".inc":
                self._device_includes.append(relative_path)

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
        """
        P = device.device_path.replace("::", "_")

        def export(name: str) -> str:
            """
            Generate a .export directive for a proc symbol.

            Usage: {{ export("_init") }}
            Output: .export __the_display_init = _the_display_init
            """
            return f".export __{P}{name} = _{P}{name}"

        def exportzp(name: str) -> str:
            """
            Generate a .exportzp directive for a zero-page symbol.
            """
            return f".exportzp __{P}{name} = {P}{name}"

        def include(name: str) -> str:
            """
            Generate a .import directive with scope alias.

            Usage: {{ include("_init") }}
            Output:
                .import   __the_display_init
                init       = __the_display_init
            """
            alias = name.lstrip("_")
            symbol = f"__{P}{name}"
            return f"    .import   {symbol}\n    {alias:<10s} = {symbol}"

        def includezp(name: str) -> str:
            """
            Generate a .importzp directive with scope alias.
            """
            alias = name.lstrip("_")
            symbol = f"__{P}{name}"
            return f"    .importzp {symbol}\n    {alias:<10s} = {symbol}"

        context: dict = {
            "device_id": str(device.id),
            "macro_prefix": P,
            "component_type": device.component_type,
            "export": export,
            "exportzp": exportzp,
            "include": include,
            "includezp": includezp,
        }
        for f in dataclasses.fields(device):
            if f.name not in device._internal_fields:
                context[f.name] = getattr(device, f.name)

        # Expose cached properties (e.g. port, bitmask, exclusive_port).
        for name in dir(type(device)):
            if isinstance(getattr(type(device), name, None), cached_property) and name not in device._internal_fields:
                context[name] = getattr(device, name)

        # Expose the bus device reference for register name generation.
        bus_device = getattr(device, "bus_device", None)
        if bus_device is not None:
            context["bus_device"] = bus_device

        return context
