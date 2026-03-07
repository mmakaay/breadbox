from __future__ import annotations

import dataclasses
from typing import TYPE_CHECKING

from rich.console import Console

if TYPE_CHECKING:
    from breadbox.types.component import Component


class ConfigPrinter:
    def __init__(self, console: Console | None = None):
        self.console = console or Console()
        self._depth = 0

    def visit(self, component: Component) -> None:
        indent = "  " * self._depth
        self.console.print(f"{indent}[blue]{component.id}[/blue] [dim]({component.component_type})[/dim]")

        for f in dataclasses.fields(component):
            if f.name in component._internal_fields:
                continue
            value = getattr(component, f.name)
            if isinstance(value, list):
                self.console.print(f"{indent}  [bold]{f.name}[/bold]:")
                for item in value:
                    self.console.print(f"{indent}    - {item}")
            else:
                self.console.print(f"{indent}  [bold]{f.name}[/bold]: {value}")

        self._depth += 1
        for sub in component.children:
            sub.accept(self)
        self._depth -= 1
