from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.settings import ViaW65c22Settings
from breadbox.config import BreadboxConfig


def resolve(config: BreadboxConfig, device_settings: dict[str, Any]) -> ViaW65c22Device:
    settings = ViaW65c22Settings.model_validate(device_settings, extra="forbid")
    return ViaW65c22Device(settings=settings)
