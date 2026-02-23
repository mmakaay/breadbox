from typing import Any

from breadbox.components.gpio_pin import component as gpio_pin_component
from breadbox.components.gpio_group import component as gpio_pin_group
from breadbox.components.lcd_hd44780.device import LcdHd44780Device
from breadbox.components.lcd_hd44780.settings import LcdHd44780Settings
from breadbox.config import BreadboxConfig
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(
    breadbox: BreadboxConfig,
    device_id: DeviceIdentifier,
    device_settings: dict[str, Any],
) -> LcdHd44780Device:
    settings = LcdHd44780Settings.model_validate(device_settings)

    en_pin = gpio_pin_component.resolve(
        breadbox,
        DeviceIdentifier("PIN_EN"),
        {
            "bus": settings.cmnd.bus,
            "pin": settings.cmnd.en_pin,
            "direction": "out",
        }
    )

    rs_pin = gpio_pin_component.resolve(
        breadbox,
        DeviceIdentifier("PIN_RS"),
        {
            "bus": settings.cmnd.bus,
            "pin": settings.cmnd.rs_pin,
            "direction": "out",
        }
    )

    rwb_pin = gpio_pin_component.resolve(
        breadbox,
        DeviceIdentifier("PIN_RWB"),
        {
            "bus": settings.cmnd.bus,
            "pin": settings.cmnd.rwb_pin,
            "direction": "out",
        }
    )

    mode = settings.data.mode.upper()
    if mode == "4BIT":
        bits = [4, 5, 6, 7]
    elif mode == "8BIT":
        bits = [0, 1, 2, 3, 4, 5, 6, 7]
    else:
        raise ValueError(f"Invalid data.mode {mode!r} for device {device_id!r} (expected: 4BIT or 8BIT)")
    data_port = gpio_pin_group.resolve(
        breadbox,
        DeviceIdentifier("DATA"),
        {
            "bus": settings.data.bus,
            "port": settings.data.port,
            "bits": bits,
        }
    )

    device = LcdHd44780Device(
        id=device_id,
        settings=settings,
        rs_pin=rs_pin,
        rwb_pin=rwb_pin,
        en_pin=en_pin,
        data_port=data_port,
    )

    return device
