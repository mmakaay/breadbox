from typing import Any

from breadbox.components.lcd_hd44780.settings import LcdHd44780Settings
from breadbox.types.device import Device


class LcdHd44780Device(Device):
    component_type: str = "lcd_hd4470"
    settings: LcdHd44780Settings

    rs_pin: Device
    rwb_pin: Device
    en_pin: Device
    data_port: Device

    def model_post_init(self, context: Any, /) -> None:
        self.en_pin.parent = self
        self.rs_pin.parent = self
        self.rwb_pin.parent = self
        self.data_port.parent = self

    def get_sub_devices(self) -> list[Device[Any]]:
        return [self.rs_pin, self.rwb_pin, self.en_pin, self.data_port]
