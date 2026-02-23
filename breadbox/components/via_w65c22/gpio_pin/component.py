from typing import Any

from breadbox.components.gpio_pin.abstract_gpio_pin_device import AbstractGpioPinDevice
from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_pin.device import ViaW65c22GpioPinDevice
from breadbox.components.via_w65c22.gpio_pin.settings import ViaW65c22GpioPinSettings
from breadbox.config import BreadboxConfig


def resolve(config: BreadboxConfig, bus_device: ViaW65c22Device, device_settings: dict[str, Any]) -> AbstractGpioPinDevice:
    combined_settings = {**device_settings, "bus_device": bus_device}
    settings = ViaW65c22GpioPinSettings.model_validate(combined_settings, extra="forbid")
    return ViaW65c22GpioPinDevice(settings=settings)
