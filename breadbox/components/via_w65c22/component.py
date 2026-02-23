from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.settings import ViaW65c22Settings
from breadbox.config import BreadboxConfig
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(breadbox: BreadboxConfig, device_id: DeviceIdentifier, device_settings: dict[str, Any]) -> ViaW65c22Device:
    settings = ViaW65c22Settings.model_validate(device_settings, extra="forbid")
    return ViaW65c22Device(id=device_id, settings=settings)
