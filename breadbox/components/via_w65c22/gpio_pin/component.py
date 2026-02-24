from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_pin.device import ViaW65c22GpioPinDevice
from breadbox.config import BreadboxConfig
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(
    breadbox: BreadboxConfig,
    device_id: DeviceIdentifier,
    bus_device: ViaW65c22Device,
    device_settings: dict[str, Any],
) -> Device:
    return ViaW65c22GpioPinDevice(id=device_id, bus_device=bus_device, **device_settings)
