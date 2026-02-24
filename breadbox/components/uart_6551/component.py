from typing import Any

from breadbox.components.gpio_pin import component as gpio_pin_component
from breadbox.components.uart_6551.device import Uart6551Device
from breadbox.config import BreadboxConfig
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(
    breadbox: BreadboxConfig,
    device_id: DeviceIdentifier,
    device_settings: dict[str, Any],
) -> Device:
    rts_settings = device_settings.pop("rts", None)

    device = Uart6551Device(id=device_id, **device_settings)

    if rts_settings is not None:
        device.add(
            gpio_pin_component.resolve(
                breadbox,
                DeviceIdentifier("PIN_RTS"),
                {**rts_settings, "direction": "out"},
            )
        )

    return device
