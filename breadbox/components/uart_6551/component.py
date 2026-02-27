from typing import Any

from breadbox.components.gpio_pin import component as gpio_pin_component
from breadbox.components.uart_6551.device import Uart6551Device
from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    device_settings: dict[str, Any],
) -> Component:
    rts_settings = device_settings.pop("rts", None)

    device = Uart6551Device(id=component_id, **device_settings)

    if rts_settings is not None:
        device.add(
            gpio_pin_component.resolve(
                breadbox,
                ComponentIdentifier("PIN_RTS"),
                {**rts_settings, "direction": "out"},
            )
        )

    return device
