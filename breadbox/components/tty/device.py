from __future__ import annotations

from dataclasses import dataclass

from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier
from breadbox.types.device import Device


@dataclass(kw_only=True)
class TtyDevice(Device):
    keyboard: ComponentIdentifier
    keyboard_device: Component

    screen: ComponentIdentifier
    screen_device: Component

    def __post_init__(self) -> None:
        super().__post_init__()
        self._internal_fields.add("keyboard_device")
        self._internal_fields.add("screen_device")
