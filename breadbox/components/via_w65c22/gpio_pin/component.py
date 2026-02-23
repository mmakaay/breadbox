from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_pin.device import ViaW65c22GpioPinDevice
from breadbox.components.via_w65c22.gpio_pin.settings import ViaW65c22GpioPinSettings
from breadbox.config import BreadboxConfig
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(
        breadbox: BreadboxConfig,
        device_id: DeviceIdentifier,
        bus_device: ViaW65c22Device,
        device_settings: dict[str, Any],
) -> Device:
    combined_settings = {**device_settings, "bus_device": bus_device}
    settings = ViaW65c22GpioPinSettings.model_validate(combined_settings, extra="forbid")
    return ViaW65c22GpioPinDevice(id=device_id, settings=settings)
