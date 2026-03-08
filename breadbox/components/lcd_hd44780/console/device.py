from dataclasses import dataclass, field

from breadbox.components.lcd_hd44780.device import LcdHd44780Device
from breadbox.types.device import Device


@dataclass(kw_only=True)
class LcdHc44780Console(Device):
    provider_device: LcdHd44780Device
    provider: str
    width: int = field(init=False)
    height: int = field(init=False)

    def __post_init__(self) -> None:
        super().__post_init__()
        self._internal_fields.add("provider_device")
        self.width = self.provider_device.width
        self.height = self.provider_device.height
