from __future__ import annotations

from breadbox.components.gpio_pin.settings import GpioPinSettings
from breadbox.components.via_w65c22.device import ViaW65c22Device


class ViaW65c22GpioPinSettings(GpioPinSettings):
    bus_device: ViaW65c22Device
