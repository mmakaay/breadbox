from __future__ import annotations

import dataclasses
import shutil
from functools import cached_property
from pathlib import Path
from typing import TYPE_CHECKING

from jinja2 import Environment, FileSystemLoader, StrictUndefined
from rich.console import Console

from breadbox.project import BreadboxProject

if TYPE_CHECKING:
    from breadbox.types.component import Component

COMPONENTS_DIR = Path(__file__).parent / "components"
TEMPLATES_DIR = Path(__file__).parent / "templates"
STDLIB_DIR = Path(__file__).parent / "stdlib"

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
    Walks the resolved component tree and generates ca65 assembly output.

    Implements the ComponentVisitor protocol to traverse the component hierarchy.
    Each component can ship assembly source files in a src/ directory alongside
    its Python code. The generator processes these through Jinja2 and writes
    the output to the target directory.

    All generated .inc files are automatically wrapped with .ifndef include
    guards derived from their output path (e.g. core/boot.inc -> __CORE_BOOT_INC).
    """

    def __init__(self, breadbox: BreadboxProject) -> None:
        self.breadbox = breadbox
        self._template_env = self._create_template_env()
        self._component_includes: list[Path] = []

    def generate(self) -> None:
        """
        Generate all assembly output from the resolved config.
        """
        self._prepare_build_dir()
        self._process_stdlib()
        self._process_project_sources()
        for component in self.breadbox.config.components.values():
            if component.parent is None:
                component.accept(self)
        self._generate_hardware_inc()
        self._generate_breadbox_inc()
        self._generate_linker_cfg()

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

    def _process_stdlib(self) -> None:
        """
        Process stdlib source files through Jinja2 with stdlib-specific context.
        """
        if not STDLIB_DIR.is_dir():
            return

        src_files = sorted(STDLIB_DIR.rglob("*"))
        src_files = [f for f in src_files if f.is_file() and f.suffix in (".s", ".inc")]
        if not src_files:
            return

        env = Environment(
            loader=FileSystemLoader(str(STDLIB_DIR)),
            undefined=StrictUndefined,
            keep_trailing_newline=True,
            lstrip_blocks=True,
            trim_blocks=True,
        )
        env.filters["hex"] = _hex_filter

        for src_file in src_files:
            relative = src_file.relative_to(STDLIB_DIR)
            output_path = Path("stdlib") / relative
            context = self._build_stdlib_context(src_file.stem)
            template = env.get_template(str(relative))
            rendered = template.render(context)
            console.print(f"  Create: {output_path}")
            self._write_generated_output(output_path, rendered)

    def _process_project_sources(self) -> None:
        """
        Discover and copy project source files to the build directory.
        """
        project_output_dir = self.breadbox.build_dir / "project"
        if project_output_dir.exists():
            shutil.rmtree(project_output_dir)
        project_output_dir.mkdir(parents=True)

        src_files = sorted(f for f in self.breadbox.project_dir.iterdir() if f.suffix in (".s", ".inc"))
        for src in src_files:
            if src.suffix in {".s", ".inc"}:
                dest = project_output_dir / src.name
                console.print(f"  Create: {dest}")
                shutil.copy2(src, dest)

    def visit(self, component: Component) -> None:
        """
        Process a component and recurse into its children.
        """
        self._process_component_sources(component)
        for sub in component.children:
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
        component-generated include files.
        """
        template = self._template_env.get_template("breadbox.inc")
        rendered = template.render(component_includes=self._component_includes)
        self._write_generated_output(Path("breadbox.inc"), rendered)

    def _generate_hardware_inc(self) -> None:
        """
        Generate hardware definitions (constants, macros) from component tree.
        """
        template = self._template_env.get_template("hardware.inc")
        rendered = template.render(components=self.breadbox.config.components)
        self._write_generated_output(Path("hardware.inc"), rendered)

    def _generate_linker_cfg(self) -> None:
        """
        Generate the ld65 linker configuration.

        If the project directory contains a linker.cfg, it is used as a
        Jinja2 template (with the resolved memory layout as context) instead
        of the built-in template.
        """
        project_cfg = self.breadbox.project_dir / "linker.cfg"
        if project_cfg.is_file():
            env = Environment(
                loader=FileSystemLoader(str(self.breadbox.project_dir)),
                undefined=StrictUndefined,
                keep_trailing_newline=True,
                lstrip_blocks=True,
                trim_blocks=True,
            )
            env.filters["hex"] = _hex_filter
            template = env.get_template("linker.cfg")
        else:
            template = self._template_env.get_template("linker.cfg")
        context = self._build_linker_context()
        rendered = template.render(context)
        self._write_generated_output(Path("linker.cfg"), rendered)

    def _build_linker_context(self) -> dict:
        """
        Build the Jinja2 template context for linker.cfg generation.
        """
        layout = self.breadbox.config.memory_layout
        if layout is None:
            return {"regions": [], "segments": []}
        return {
            "regions": layout.regions,
            "segments": layout.segments,
        }

    def _process_component_sources(self, component: Component) -> None:
        """
        Process a component's assembly source files into the output directory.

        Uses the component's component_dir (via inspect) to locate the src/
        directory. Output files are placed under the component's build_dir,
        which mirrors the component tree (e.g. the_display/pin_rs/).

        api.inc is auto-generated from metadata collected during rendering
        of other templates (via api() and exportzp() calls).
        """
        src_dir = component.component_dir / "src"
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

        context = self._build_context(component)

        # Phase 1: render all files except api.inc (collecting api/exportzp metadata).
        src_files = sorted(f for f in src_dir.iterdir() if f.suffix in (".s", ".inc"))
        for src_file in src_files:
            if src_file.name == "api.inc":
                continue
            template = env.get_template(src_file.name)
            rendered = template.render(context)
            if src_file.suffix == ".s":
                rendered = self._inject_exports(rendered, context)
            relative_path = component.component_path / src_file.name
            console.print(f"  Create: {relative_path}")
            self._write_generated_output(relative_path, rendered)

        # Phase 2: auto-generate api.inc from collected metadata.
        api_inc = self._generate_api_inc(component, context)
        if api_inc is not None:
            relative_path = component.component_path / "api.inc"
            console.print(f"  Create: {relative_path}")
            self._write_generated_output(relative_path, api_inc)
            self._component_includes.append(relative_path)
        elif (src_dir / "api.inc").is_file():
            # Fallback: render template-based api.inc (e.g. CORE component).
            template = env.get_template("api.inc")
            rendered = template.render(context)
            relative_path = component.component_path / "api.inc"
            console.print(f"  Create: {relative_path}")
            self._write_generated_output(relative_path, rendered)
            self._component_includes.append(relative_path)

    @staticmethod
    def _generate_api_inc(component: Component, context: dict) -> str | None:
        """
        Auto-generate api.inc from metadata collected during template rendering.

        Returns None if the component has no API functions or exported ZP variables.
        """
        api_defs: list[str] = context["_api_defs"]
        zp_defs: list[str] = context["_zp_defs"]
        P = context["symbol_prefix"]
        component_path = component.component_path

        if not api_defs and not zp_defs:
            return None

        lines: list[str] = [
            f".include \"{component_path}/macros.inc\"",
            f".include \"{component_path}/macros.inc\"",
            "",
            f".scope {P}",
        ]

        for name in zp_defs:
            sym = f"__{P}_{name}"
            lines.append(f"    .importzp {sym}")
            lines.append(f"    {name} = {sym}")

        if zp_defs and api_defs:
            lines.append("")

        for name in api_defs:
            sym = f"__{P}_{name}"
            lines.append(f"    .import {sym}")
            lines.append(f"    {name} = {sym}")

        lines.append("")
        lines.append(".endscope")
        lines.append("")

        return "\n".join(lines)

    @staticmethod
    def _inject_exports(rendered: str, context: dict) -> str:
        """
        Inject .export/.exportzp directives into a rendered .s file.

        Uses metadata collected by api_def() and zp_def() during rendering.
        Directives are inserted before the first .segment directive to match
        the project convention (includes → exports → code).
        """
        api_defs: list[str] = context["_api_defs"]
        zp_defs: list[str] = context["_zp_defs"]
        P: str = context["symbol_prefix"]

        if not api_defs and not zp_defs:
            return rendered

        export_lines: list[str] = []
        for name in zp_defs:
            export_lines.append(f".exportzp __{P}_{name}")
        if zp_defs and api_defs:
            export_lines.append("")
        for name in api_defs:
            export_lines.append(f".export __{P}_{name}")

        export_block = "\n".join(export_lines)

        # Insert before the first .segment directive.
        lines = rendered.split("\n")
        for i, line in enumerate(lines):
            if line.strip().startswith(".segment"):
                lines.insert(i, "")
                lines.insert(i, export_block)
                return "\n".join(lines)

        # No .segment found — append at end.
        return rendered.rstrip("\n") + "\n\n" + export_block + "\n"

    _BANNER = "Auto-generated by breadbox. Do not edit."

    def _write_generated_output(self, relative_path: Path, content: str) -> None:
        """
        Write generated content to the output directory.

        Prepends the auto-generation banner and, for .inc files, wraps
        content with .ifndef include guards derived from the output path.
        """
        prefix = "#" if relative_path.suffix == ".cfg" else ";"
        content = f"{prefix} {self._BANNER}\n{content}"
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
    def _build_stdlib_context(prefix: str) -> dict:
        """
        Build the Jinja2 template context for a stdlib file.

        Stdlib files get a symbol() helper keyed on the file stem
        (e.g. divmod16 -> __divmod16_name).
        """

        def symbol(name: str) -> str:
            return f"__{prefix}_{name}"

        return {"symbol": symbol}


    def _build_context(self, component: Component) -> dict:
        """
        Build the Jinja2 template context for a component.
        """
        P = component.symbol_prefix
        _api_defs: list[str] = []
        _zp_defs: list[str] = []

        def api_def(name: str) -> str:
            """
            Define a public API subroutine: __{P}_{name}.

            Registers the name for auto-generation of .export and api.inc.
            Use at .proc sites for public API functions.
            """
            if name not in _api_defs:
                _api_defs.append(name)
            return f"__{P}_{name}"

        def api(name: str) -> str:
            """Reference a public API subroutine: __{P}_{name}."""
            return f"__{P}_{name}"

        def my_def(name: str) -> str:
            """
            Define an internal subroutine: __{P}_{name}.

            Use at .proc sites for component-internal functions.
            """
            return f"__{P}_{name}"

        def my(name: str) -> str:
            """Reference an internal symbol: __{P}_{name}."""
            return f"__{P}_{name}"

        def zp_def(name: str) -> str:
            """
            Define a user-facing zero-page variable: __{P}_{name}.

            Registers the name for auto-generation of .exportzp and api.inc.
            Use at .res label sites for ZP variables exposed in the public API.
            """
            if name not in _zp_defs:
                _zp_defs.append(name)
            return f"__{P}_{name}"

        def zp(name: str) -> str:
            """Reference a user-facing zero-page variable: __{P}_{name}."""
            return f"__{P}_{name}"

        def var(name: str) -> str:
            """Reference or define an internal data symbol: __{P}_{name}."""
            return f"__{P}_{name}"

        def constant(name: str) -> str:
            """Generate a public constant name: {P}_{name}."""
            return f"{P}_{name}"

        context: dict = {
            "component_id": str(component.id),
            "symbol_prefix": P,
            "component_type": component.component_type,
            "api_def": api_def,
            "api": api,
            "my_def": my_def,
            "my": my,
            "zp_def": zp_def,
            "zp": zp,
            "var": var,
            "constant": constant,
            "symbol": var,  # backward compat for CORE templates
            "_api_defs": _api_defs,
            "_zp_defs": _zp_defs,
        }
        for f in dataclasses.fields(component):
            if f.name not in component._internal_fields:
                context[f.name] = getattr(component, f.name)

        # Expose cached properties (e.g. port, bitmask, exclusive_port).
        for name in dir(type(component)):
            if (
                isinstance(getattr(type(component), name, None), cached_property)
                and name not in component._internal_fields
            ):
                context[name] = getattr(component, name)

        # Expose the bus device reference for register name generation.
        bus_device = getattr(component, "bus_device", None)
        if bus_device is not None:
            context["bus_device"] = bus_device

        return context
