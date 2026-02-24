from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.config import BreadboxConfig
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(breadbox: BreadboxConfig, device_id: DeviceIdentifier, device_settings: dict[str, Any]) -> ViaW65c22Device:
    return ViaW65c22Device(id=device_id, **device_settings)
