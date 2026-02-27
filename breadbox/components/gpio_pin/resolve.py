from typing import Any

from breadbox.components.bus_delegation import resolve_via_bus
from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(breadbox: BreadboxConfig, component_id: ComponentIdentifier, device_settings: dict[str, Any]) -> Component:
    return resolve_via_bus(breadbox, component_id, device_settings, interface_name="gpio_pin")
