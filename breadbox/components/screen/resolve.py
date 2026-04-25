from typing import Any

from breadbox.components.resolve_via_provider import resolve_via_provider
from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(breadbox: BreadboxConfig, component_id: ComponentIdentifier, device_settings: dict[str, Any]) -> Component:
    return resolve_via_provider(
        breadbox=breadbox,
        component_id=component_id,
        device_settings=device_settings,
        interface_name="screen",
    )
