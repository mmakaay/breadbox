from typing import Any

from breadbox.components.gpio_group import resolve as gpio_group_resolve
from breadbox.components.gpio_pin import resolve as gpio_pin_resolve
from breadbox.components.lcd_hd44780.device import CmndSettings, DataSettings, LcdHd44780Device
from breadbox.config import BreadboxConfig
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    device_settings: dict[str, Any],
) -> LcdHd44780Device:
    cmnd = CmndSettings(**device_settings["cmnd"])
    data = DataSettings(**device_settings["data"])

    # Pin ordering convention: CTRL pins = [RS, RWB] (semantic order matters for LCD mode constants)
    device = LcdHd44780Device(id=component_id, mode=data.mode)

    device.add(
        gpio_group_resolve.resolve(
            breadbox,
            ComponentIdentifier("CTRL"),
            {"bus": cmnd.bus, "pins": [cmnd.rs_pin, cmnd.rwb_pin], "direction": "out"},
        )
    )

    device.add(
        gpio_pin_resolve.resolve(
            breadbox,
            ComponentIdentifier("PIN_EN"),
            {"bus": cmnd.bus, "pin": cmnd.en_pin, "direction": "out"},
        )
    )

    mode = data.mode.upper()
    if mode == "4BIT":
        bits = 0b11110000
    elif mode == "8BIT":
        bits = 0b11111111
    else:
        raise ValueError(f"Invalid data.mode {mode!r} for component {component_id!r} (expected: 4BIT or 8BIT)")

    device.add(
        gpio_group_resolve.resolve(
            breadbox,
            ComponentIdentifier("DATA"),
            {"bus": data.bus, "port": data.port, "bits": bits},
        )
    )

    return device
