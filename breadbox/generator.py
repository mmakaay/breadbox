from __future__ import annotations

import dataclasses
import shutil
from functools import cached_property
from pathlib import Path
from typing import TYPE_CHECKING

from jinja2 import Environment, FileSystemLoader, StrictUndefined
from rich.console import Console

from breadbox.project import BreadboxProject
from breadbox.types.component import Component

if TYPE_CHECKING:
    pass

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


def _bin_filter(value: int) -> str:
    """
    Format an integer as a ca65 binary literal (%bbbb or %bbbbbbbb).
    """
    if value <= 0xFF:
        return f"%{value:04b}"
    return f"%{value:08b}"


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
        self._template_env = self._create_jinja2_env(TEMPLATES_DIR)
        self._component_includes: list[Path] = []

    def generate(self) -> None:
        """
        Generate all assembly output from the resolved config.
        """
        self._prepare_build_dir()
        self._process_stdlib()
        self._process_extra_sources()
        for component in self.breadbox.config.components.values():
            if component.parent is None:
                component.accept(self)
        self._process_project_sources()
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

        env = self._create_jinja2_env(STDLIB_DIR)

        for src_file in src_files:
            relative = src_file.relative_to(STDLIB_DIR)
            output_path = Path("stdlib") / relative
            context = self._build_stdlib_context(src_file.stem)
            template = env.get_template(str(relative))
            rendered = template.render(context)
            self._write_generated_output(output_path, rendered)

    def _process_extra_sources(self) -> None:
        """
        Process extra source directories registered during config resolution.
        """
        seen: set[str] = set()
        for output_prefix, src_dir in self.breadbox.config.extra_source_dirs:
            # Avoid directory collisions on case-insensitive file systems.
            # A `TICKER` device would otherwise conflict with the `ticker` component,
            # since both write sources under `build/breadbox/...`. Without the added
            # underscores we could end up with `ticker` and `TICKER`, which resolve
            # to the same directory on systems like macOS.
            output_prefix = f"__{output_prefix}"

            if output_prefix in seen:
                continue
            seen.add(output_prefix)

            env = self._create_jinja2_env(src_dir)

            src_files = sorted(f for f in src_dir.iterdir() if f.suffix in (".s", ".inc"))
            for src_file in src_files:
                template = env.get_template(src_file.name)
                rendered = template.render()
                output_path = Path(output_prefix) / src_file.name
                self._write_generated_output(output_path, rendered)

                # Automatically add shared include files to breadbox.inc:
                #   *macros.inc  — assembly macros shared across implementations
                #   constants.inc — interface-level constants (e.g. keyboard key codes)
                if src_file.name.endswith("macros.inc") or src_file.name == "constants.inc":
                    self._component_includes.append(output_path)

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

    def _create_jinja2_env(self, template_path: Path) -> Environment:
        """
        Create Jinja2 environment for the provided template path.
        """
        env = Environment(
            loader=FileSystemLoader(str(template_path)),
            undefined=StrictUndefined,
            keep_trailing_newline=True,
            lstrip_blocks=True,
            trim_blocks=True,
        )
        env.filters["hex"] = _hex_filter
        env.filters["bin"] = _bin_filter
        env.globals["config"] = self.breadbox.config
        return env

    def _generate_breadbox_inc(self) -> None:
        """
        Generate the main include file (breadbox.inc).

        Pulls in hardware definitions, core assembly, and all
        component-generated include files.
        """
        template = self._template_env.get_template("breadbox.inc")
        rendered = template.render(component_includes=self._component_includes)
        self._write_generated_output(Path("breadbox.inc"), rendered)

    def _generate_linker_cfg(self) -> None:
        """
        Generate the ld65 linker configuration.

        If the project directory contains a linker.cfg, it is used as a
        Jinja2 template (with the resolved memory layout as context) instead
        of the built-in template.
        """
        project_cfg = self.breadbox.project_dir / "linker.cfg"
        if project_cfg.is_file():
            env = self._create_jinja2_env(self.breadbox.project_dir)
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

        self._reset_render_tracking()

        env = self._create_jinja2_env(src_dir)
        context = self._build_context(component)

        # Phase 1: render all files except api.inc (collecting api/exportzp metadata).
        src_files = sorted(f for f in src_dir.iterdir() if f.suffix in (".s", ".inc"))
        for src_file in src_files:
            if src_file.name == "api.inc":
                continue
            template = env.get_template(src_file.name)
            rendered = template.render(context)
            if src_file.suffix == ".s":
                import_api_defs, import_zp_defs = self._collect_render_imports(component)
                rendered = self._inject_directives(
                    rendered,
                    component,
                    import_api_defs,
                    import_zp_defs,
                    component._render_file_api_defs,
                    component._render_file_zp_defs,
                )
                self._clear_file_render_tracking()
            relative_path = component.component_path / src_file.name
            self._write_generated_output(relative_path, rendered)
            if src_file.name.endswith("macros.inc"):
                context["_macro_includes"].append(relative_path)

        # Phase 2: auto-generate api.inc from collected metadata.
        # If the component contains an api.inc file, that one is used.
        # Otherwise, an api.inc is generated, based on the collected data.
        if (src_dir / "api.inc").is_file():
            template = env.get_template("api.inc")
            rendered = template.render(context)
            relative_path = component.component_path / "api.inc"
            self._write_generated_output(relative_path, rendered)
            self._component_includes.append(relative_path)
        else:
            api_inc = self._generate_api_inc(component, context["_macro_includes"])
            if api_inc is not None:
                relative_path = component.component_path / "api.inc"
                self._write_generated_output(relative_path, api_inc)
                self._component_includes.append(relative_path)

    def _reset_render_tracking(self) -> None:
        for component in self._iter_components():
            component._reset_render_tracking()

    def _clear_file_render_tracking(self) -> None:
        for component in self._iter_components():
            component._render_file_api_defs.clear()
            component._render_file_zp_defs.clear()
            component._render_api_refs.clear()
            component._render_zp_refs.clear()

    def _collect_render_imports(
        self, component: Component
    ) -> tuple[list[tuple[Component, str]], list[tuple[Component, str]]]:
        api_defs: list[tuple[Component, str]] = []
        zp_defs: list[tuple[Component, str]] = []
        for candidate in self._iter_components():
            if candidate is component:
                continue
            for name in candidate._render_api_refs:
                api_defs.append((candidate, name))
            for name in candidate._render_zp_refs:
                zp_defs.append((candidate, name))
        return api_defs, zp_defs

    def _iter_components(self) -> list[Component]:
        seen: set[int] = set()
        ordered: list[Component] = []
        stack = list(self.breadbox.config.components.values())
        while stack:
            component = stack.pop()
            identity = id(component)
            if identity in seen:
                continue
            seen.add(identity)
            ordered.append(component)
            stack.extend(reversed(component.children))
        return ordered

    @staticmethod
    def _generate_api_inc(component: Component, macro_includes: list[Path]) -> str | None:
        """
        Auto-generate api.inc from metadata collected during template rendering.
        """
        lines: list[str] = []
        api_defs = component._render_api_defs
        zp_defs = component._render_zp_defs

        if not api_defs and not zp_defs and not macro_includes:
            return None

        # Include macro files so they are available to all consumers.
        for inc_path in macro_includes:
            lines.append(f'.include "{inc_path}"')
        if macro_includes:
            lines.append("")

        # Import directives go outside the scope so the raw symbols
        # (e.g. __LCD_DATA_write) are globally visible. This allows both
        # scoped access (LCD_DATA::write) and direct references via
        # device.api("write") in templates.
        for name in zp_defs:
            lines.append(f".importzp {component.zp(name)}")
        for name in api_defs:
            lines.append(f".import {component.api(name)}")
        lines.append("")

        # Scope block provides short aliases for consumer code.
        lines.append(f".scope {component.scope}")
        for name in zp_defs:
            lines.append(f"    {name} = {component.zp(name)}")
        if zp_defs and api_defs:
            lines.append("")
        for name in api_defs:
            lines.append(f"    {name} = {component.api(name)}")
        lines.append("")
        lines.append(".endscope")
        lines.append("")

        return "\n".join(lines)

    @staticmethod
    def _inject_directives(
        rendered: str,
        component: Component,
        import_api_defs: list[tuple[Component, str]],
        import_zp_defs: list[tuple[Component, str]],
        export_api_defs: list[str],
        export_zp_defs: list[str],
    ) -> str:
        """
        Inject .import/.export directives into a rendered .s file.
        """

        if not import_api_defs and not import_zp_defs and not export_api_defs and not export_zp_defs:
            return rendered

        directive_lines: list[str] = []
        for imported_component, name in import_zp_defs:
            directive_lines.append(f".importzp {imported_component.zp(name)}")
        for imported_component, name in import_api_defs:
            directive_lines.append(f".import {imported_component.api(name)}")
        if directive_lines and (export_zp_defs or export_api_defs):
            directive_lines.append("")
        for name in export_zp_defs:
            directive_lines.append(f".exportzp {component.zp(name)}")
        if export_zp_defs and export_api_defs:
            directive_lines.append("")
        for name in export_api_defs:
            directive_lines.append(f".export {component.api(name)}")

        directive_block = "\n".join(directive_lines)

        # Insert before the first .segment directive.
        lines = rendered.split("\n")
        for i, line in enumerate(lines):
            if line.strip().startswith(".segment"):
                lines.insert(i, "")
                lines.insert(i, directive_block)
                return "\n".join(lines)

        # No .segment found — append at end.
        return rendered.rstrip("\n") + "\n\n" + directive_block + "\n"

    _BANNER = "Auto-generated by breadbox. Do not edit."

    def _write_generated_output(self, relative_path: Path, content: str) -> None:
        """
        Write generated content to the output directory.

        Prepends the auto-generation banner and, for .inc files, wraps
        content with .ifndef include guards derived from the output path.
        """
        prefix = "#" if relative_path.suffix == ".cfg" else ";"
        content = f"{prefix} {self._BANNER}\n\n{content}"
        if relative_path.suffix == ".inc":
            content = self._wrap_include_guard(content, relative_path)
        dest = self.breadbox.generated_dir / relative_path
        console.print(f"  Create: {dest}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)

    @staticmethod
    def _wrap_include_guard(content: str, relative_path: Path) -> str:
        """
        Wrap content with .ifndef include guard.

        The guard symbol is derived from the relative output path with
        a __ prefix to avoid collisions with user-defined symbols:

            core/boot.inc -> __CORE_BOOT_INC
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

    @staticmethod
    def _build_context(component: Component) -> dict:
        """
        Build the Jinja2 template context for a component.
        """
        _macro_includes: list[Path] = []

        context: dict = {
            "component": component,
            "component_id": str(component.id),
            "component_type": component.component_type,
            "api_def": component.api_def,
            "api": component.api,
            "my_def": component.my_def,
            "my": component.my,
            "zp_def": component.zp_def,
            "zp": component.zp,
            "var": component.var,
            "symbol": component.var,  # backward compat for CORE templates
            "_macro_includes": _macro_includes,
        }
        for f in dataclasses.fields(component):
            if f.name not in component._internal_fields:
                context[f.name] = getattr(component, f.name)

        for f in dataclasses.fields(component):
            if f.name in context:
                continue
            value = getattr(component, f.name)
            if isinstance(value, Component):
                context[f.name] = value

        # Expose cached properties (e.g. port, bitmask, exclusive_port).
        for name in dir(type(component)):
            if (
                isinstance(getattr(type(component), name, None), cached_property)
                and name not in component._internal_fields
            ):
                context[name] = getattr(component, name)
        return context
