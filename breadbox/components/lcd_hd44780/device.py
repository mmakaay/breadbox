from breadbox.components.lcd_hd44780.settings import LcdHd44780Settings
from breadbox.types.device import Device


class LcdHd44780Device(Device):
    component_type: str = "lcd_hd4470"
    settings: LcdHd44780Settings

    def get_info(self) -> dict[str, str]:
        return {k: str(v) for k, v in self.settings.model_dump().items()}
