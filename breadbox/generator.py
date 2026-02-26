from __future__ import annotations

import dataclasses
import shutil
from functools import cached_property
from pathlib import Path
from typing import TYPE_CHECKING

from jinja2 import Environment, FileSystemLoader, StrictUndefined
from rich.console import Console

from breadbox.errors import ConfigError
from breadbox.project import BreadboxProject
from breadbox.visitors.bus_client_collector import BusClientCollector

if TYPE_CHECKING:
    from breadbox.types.device import Device

COMPONENTS_DIR = Path(__file__).parent / "components"
TEMPLATES_DIR = Path(__file__).parent / "templates"

console = Console()


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

    def __init__(self, breadbox: BreadboxProject) -> None:
        self.breadbox = breadbox
        self._template_env = self._create_template_env()
        self._bus_collector = BusClientCollector()
        self._device_includes: list[Path] = []

    def generate(self) -> None:
        """
        Generate all assembly output from the resolved config.
        """
        self._collect_bus_clients()
        self._validate_bus_clients()

        self._prepare_build_dir()
        self._process_project_sources()
        for device in self.breadbox.config.devices.values():
            if device.parent is None:
                device.accept(self)
        self._generate_hardware_inc()
        self._generate_breadbox_inc()
        self._generate_linker_cfg()

    def _collect_bus_clients(self) -> None:
        """
        Walk the full device tree and register bus clients.

        Must run before code generation so that bus devices
        can answer queries about their clients (e.g. port exclusivity).
        """
        for device in self.breadbox.config.devices.values():
            if device.parent is None:
                device.accept(self._bus_collector)

    def _validate_bus_clients(self) -> None:
        """
        Ask each device to validate its registered bus clients.

        Wraps any ValueError from device validation as ConfigError
        so the CLI can display it cleanly without a stack trace.
        """
        for device in self.breadbox.config.devices.values():
            try:
                device.validate_bus_clients()
            except ValueError as e:
                raise ConfigError(str(e)) from None

    def _prepare_build_dir(self) -> None:
        """
        Clean and recreate the output directory.
        """
        if self.breadbox.build_dir.exists():
            shutil.rmtree(self.breadbox.build_dir)
        self.breadbox.build_dir.mkdir(parents=True)
        # Tag the build root as a cache directory for backup tools.
        (self.breadbox.build_dir / "CACHEDIR.TAG").write_text(
            "Signature: 8a477f597d28d172789f06886806bc55\n"
            "# This directory is managed by breadbox and can be safely regenerated.\n"
        )

    def _process_project_sources(self) -> None:
        """
        Discover and copy project source files to the build directory.
        """
        project_output_dir = self.breadbox.build_dir / "project"
        if project_output_dir.exists():
            shutil.rmtree(project_output_dir)
        project_output_dir.mkdir(parents=True)

        src_files = sorted(f for f in self.breadbox.project_dir.iterdir() if f.suffix in (".s", ".inc"))
        for src in  src_files:
            if src.suffix in {".s", ".inc"}:
                dest = project_output_dir / src.name
                console.print(f"  Create: {dest}")
                shutil.copy2(src, dest)

    def visit(self, device: Device) -> None:
        """
        Process a device and recurse into its sub-devices.
        """
        self._process_component_sources(device)
        for sub in device.devices:
            sub.accept(self)

    @staticmethod
    def _create_template_env() -> Environment:
        """
        Create Jinja2 environment for top-level templates.
        """
        env = Environment(
            loader=FileSystemLoader(str(TEMPLATES_DIR)),
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
        self._write_generated_output(Path("breadbox.inc"), rendered)

    def _generate_hardware_inc(self) -> None:
        """
        Generate hardware definitions (constants, macros) from device tree.
        """
        template = self._template_env.get_template("hardware.inc")
        rendered = template.render(devices=self.breadbox.config.devices)
        self._write_generated_output(Path("hardware.inc"), rendered)

    def _generate_linker_cfg(self) -> None:
        """
        Generate the ld65 linker configuration.
        """
        template = self._template_env.get_template("linker.cfg")
        rendered = template.render()
        self._write_generated_output(Path("linker.cfg"), rendered)

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
            relative_path = device.device_path / src_file.name
            console.print(f"  Create: {relative_path}")
            self._write_generated_output(relative_path, rendered)
            if src_file.name == "api.inc":
                self._device_includes.append(relative_path)

    def _write_generated_output(self, relative_path: Path, content: str) -> None:
        """
        Write generated content to the output directory.

        For .inc files, automatically wraps content with .ifndef include guards
        derived from the output path.
        """
        if relative_path.suffix == ".inc":
            content = self._wrap_include_guard(content, relative_path)
        dest = self.breadbox.generated_dir / relative_path
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

    @staticmethod
    def _build_context(device: Device) -> dict:
        """
        Build the Jinja2 template context for a device.
        """
        P = device.macro_prefix

        def symbol(name: str) -> str:
            """
            Generate a private name for a symbol, to be used internally in breadbox code.

            This ugly wrapping makes the symbol names unique (by prefixing with the `{ P }`refix,
            and by adding double underscores in front). Once these symbols reach the space of the
            public API, thet will be made properly scoped and nicer to read. E.g. the private
            symbol `__UART_write` will be exposed to projects as `UART::write`.

            We can't unfortunately not make use of scoping in symbol .export / .import, therefore
            we're forced to use this somewhat ugly name mangling.
            """
            return f"__{P}_{name}"

        def alias(name: str, alias: str | None = None) -> str:
            """
            Generates `<symbol_name>\n    <alias> = <symbol_name>`

            The name is used as the alias by default.
            Not that this is not only alias assignment, but it also echoes the
            private symbol name. The targeted use for this, are constructs like:

                .import {{ alias("do_it", "go") }}

            which will result in:

                .import __DEVICE_PATH_do_it
                go = __DEVICE_PATH_do_it
            """
            alias = alias or name
            return f"{symbol(name)}\n    {alias} = {symbol(name)}"

        context: dict = {
            "device_id": str(device.id),
            "macro_prefix": P,
            "component_type": device.component_type,
            "symbol": symbol,
            "alias": alias,
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
