from typing import Any

from breadbox.components.tty.device import TtyDevice
from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    device_settings: dict[str, Any],
) -> Component:
    input_device = breadbox.get(device_settings["input"])
    output_device = breadbox.get(device_settings["output"])
    return TtyDevice(id=component_id, input_device=input_device, output_device=output_device,  **device_settings)
