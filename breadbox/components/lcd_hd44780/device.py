from typing import Any

from breadbox.components.gpio_pin.abstract_gpio_pin_device import AbstractGpioPinDevice
from breadbox.components.lcd_hd44780.settings import LcdHd44780Settings
from breadbox.types.device import Device


class LcdHd44780Device(Device):
    component_type: str = "lcd_hd4470"
    settings: LcdHd44780Settings

    rs_pin: AbstractGpioPinDevice
    rwb_pin: AbstractGpioPinDevice
    en_pin: AbstractGpioPinDevice

    def model_post_init(self, context: Any, /) -> None:
        self.en_pin.parent = self


    def get_sub_devices(self) -> list[Device[Any]]:
        return [self.rs_pin, self.rwb_pin, self.en_pin]
