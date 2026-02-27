from typing import Any

from breadbox.components.ram.device import RamDevice
from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    device_settings: dict[str, Any],
) -> Component:
    return RamDevice(id=component_id, **device_settings)
