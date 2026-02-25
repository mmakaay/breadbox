from typing import Any

from breadbox.components.gpio_group import component as gpio_group_component
from breadbox.components.gpio_pin import component as gpio_pin_component
from breadbox.components.lcd_hd44780.device import CmndSettings, DataSettings, LcdHd44780Device
from breadbox.config import BreadboxConfig
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(
    breadbox: BreadboxConfig,
    device_id: DeviceIdentifier,
    device_settings: dict[str, Any],
) -> LcdHd44780Device:
    cmnd = CmndSettings(**device_settings["cmnd"])
    data = DataSettings(**device_settings["data"])

    device = LcdHd44780Device(id=device_id, mode=data.mode, rs_pin=cmnd.rs_pin, rwb_pin=cmnd.rwb_pin)

    device.add(
        gpio_group_component.resolve(
            breadbox,
            DeviceIdentifier("CTRL"),
            {"bus": cmnd.bus, "pins": [cmnd.rs_pin, cmnd.rwb_pin], "direction": "out"},
        )
    )

    device.add(
        gpio_pin_component.resolve(
            breadbox,
            DeviceIdentifier("PIN_EN"),
            {"bus": cmnd.bus, "pin": cmnd.en_pin, "direction": "out"},
        )
    )

    mode = data.mode.upper()
    if mode == "4BIT":
        bits = 0b11110000
    elif mode == "8BIT":
        bits = 0b11111111
    else:
        raise ValueError(f"Invalid data.mode {mode!r} for device {device_id!r} (expected: 4BIT or 8BIT)")

    device.add(
        gpio_group_component.resolve(
            breadbox,
            DeviceIdentifier("DATA"),
            {"bus": data.bus, "port": data.port, "bits": bits},
        )
    )

    device.validate_pins()

    return device
