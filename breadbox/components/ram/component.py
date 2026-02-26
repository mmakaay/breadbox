from typing import Any

from breadbox.components.ram.device import RamDevice
from breadbox.config import BreadboxConfig
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(
    breadbox: BreadboxConfig,
    device_id: DeviceIdentifier,
    device_settings: dict[str, Any],
) -> Device:
    return RamDevice(id=device_id, **device_settings)
