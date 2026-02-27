from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.config import BreadboxConfig
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(breadbox: BreadboxConfig, component_id: ComponentIdentifier, device_settings: dict[str, Any]) -> ViaW65c22Device:
    return ViaW65c22Device(id=component_id, **device_settings)
