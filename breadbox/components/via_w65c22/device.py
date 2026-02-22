from typing import Any

from breadbox.components.gpio_pin.abstract_gpio_pin_bus import AbstractGpioPinBus
from breadbox.components.gpio_pin.abstract_gpio_pin_device import AbstractGpioPinDevice
from breadbox.components.via_w65c22.gpio_pin.device import ViaW65c22GpioPinDevice
from breadbox.components.via_w65c22.gpio_pin.settings import ViaW65c22GpioPinSettings
from breadbox.components.via_w65c22.settings import ViaW65c22Settings
from breadbox.config import BreadboxConfig
from breadbox.types.device import Device


class ViaW65c22Device(AbstractGpioPinBus, Device):
    settings: ViaW65c22Settings

    def get_info(self) -> dict[str, str]:
        return {
            "address": str(self.settings.address),
        }

    def resolve_gpio_pin(self, config: BreadboxConfig, device_settings: dict[str, Any]) -> AbstractGpioPinDevice:
        settings = ViaW65c22GpioPinSettings.model_validate(device_settings, extra="forbid")
        return ViaW65c22GpioPinDevice(settings=settings)
