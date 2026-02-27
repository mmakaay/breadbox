import importlib
from typing import Any

from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve_via_bus(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    device_settings: dict[str, Any],
    interface_name: str,
    bus_key: str = "bus",
) -> Component:
    bus_id = device_settings.get(bus_key)
    if not bus_id:
        raise ValueError(f"Component {component_id!r}: missing '{bus_key}' field")
    bus_device = breadbox.get(ComponentIdentifier(bus_id))
    bus_type = bus_device.component_type
    module_name = f"breadbox.components.{bus_type}.{interface_name}.component"
    try:
        module = importlib.import_module(module_name)
    except ModuleNotFoundError:
        raise ValueError(f"Bus type {bus_type!r} does not support {interface_name} (no module {module_name})") from None
    return module.resolve(breadbox, component_id, bus_device, device_settings)
