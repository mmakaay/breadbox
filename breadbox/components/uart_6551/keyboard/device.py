from dataclasses import dataclass

from breadbox.components.uart_6551.device import Uart6551Device
from breadbox.types.device import Device


@dataclass(kw_only=True)
class Uart6551Keyboard(Device):
    provider_device: Uart6551Device
    provider: str

    def __post_init__(self) -> None:
        super().__post_init__()
        self._internal_fields.add("provider_device")
