from typing import Any

from breadbox.components.core.device import CoreDevice
from breadbox.config import BreadboxConfig
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(breadbox: BreadboxConfig, device_id: DeviceIdentifier, device_settings: dict[str, Any]) -> CoreDevice:
    return CoreDevice(id=device_id, **device_settings)
