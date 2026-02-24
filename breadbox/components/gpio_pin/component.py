from typing import Any

from breadbox.components.bus_delegation import resolve_via_bus
from breadbox.config import BreadboxConfig
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(breadbox: BreadboxConfig, device_id: DeviceIdentifier, device_settings: dict[str, Any]) -> Device:
    return resolve_via_bus(breadbox, device_id, device_settings, interface_name="gpio_pin")
