from typing import Any

from breadbox.components.core.device import CoreDevice
from breadbox.config import BreadboxConfig
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(breadbox: BreadboxConfig, component_id: ComponentIdentifier, device_settings: dict[str, Any]) -> CoreDevice:
    return CoreDevice(id=component_id, **device_settings)
