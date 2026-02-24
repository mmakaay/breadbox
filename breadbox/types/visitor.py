from __future__ import annotations

from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    from breadbox.types.device import Device


class DeviceVisitor(Protocol):
    def visit(self, device: Device) -> None: ...
