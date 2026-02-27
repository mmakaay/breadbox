from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_pin.device import ViaW65c22GpioPinDevice
from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    bus_device: ViaW65c22Device,
    device_settings: dict[str, Any],
) -> Component:
    return ViaW65c22GpioPinDevice(id=component_id, bus_device=bus_device, **device_settings)
