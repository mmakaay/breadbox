from typing import Any

from breadbox.components.rom.device import RomDevice
from breadbox.config import BreadboxConfig
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(
    breadbox: BreadboxConfig,
    device_id: DeviceIdentifier,
    device_settings: dict[str, Any],
) -> Device:
    return RomDevice(id=device_id, **device_settings)
