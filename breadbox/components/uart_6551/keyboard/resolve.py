from typing import Any

from breadbox.components.uart_6551.device import Uart6551Device
from breadbox.components.uart_6551.keyboard.device import Uart6551Keyboard
from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    provider_device: Uart6551Device,
    device_settings: dict[str, Any],
) -> Component:
    return Uart6551Keyboard(id=component_id, provider_device=provider_device, **device_settings)
