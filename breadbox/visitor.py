from __future__ import annotations

import dataclasses
from typing import TYPE_CHECKING, Protocol

from rich.console import Console

if TYPE_CHECKING:
    from breadbox.types.device import Device


class DeviceVisitor(Protocol):
    def visit(self, device: Device) -> None: ...


class ConfigPrinter:
    def __init__(self, console: Console | None = None):
        self.console = console or Console()
        self._depth = 0

    def visit(self, device: Device) -> None:
        indent = "  " * self._depth
        self.console.print(f"{indent}[blue]{device.id}[/blue] [dim]({device.component_type})[/dim]")

        for f in dataclasses.fields(device):
            if f.name in device._internal_fields:
                continue
            value = getattr(device, f.name)
            self.console.print(f"{indent}  [bold]{f.name}[/bold]: {value}")

        self._depth += 1
        for sub in device.devices:
            sub.accept(self)
        self._depth -= 1
