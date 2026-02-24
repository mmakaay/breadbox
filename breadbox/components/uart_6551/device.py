from dataclasses import dataclass, field

from breadbox.types.address16 import Address16
from breadbox.types.device import Device
from breadbox.types.on_off import OnOff

UART_TYPES = ("w65c51", "um6551", "m6551", "generic")


@dataclass(kw_only=True)
class Uart6551Device(Device):
    type: str = "generic"
    address: Address16
    irq: OnOff = field(default=OnOff("on"))

    def __post_init__(self) -> None:
        super().__post_init__()
        self.type = self.type.lower()
        if self.type not in UART_TYPES:
            raise ValueError(
                f"Invalid UART type {self.type!r} "
                f"(expected one of: {', '.join(UART_TYPES)})"
            )
