from __future__ import annotations

from dataclasses import dataclass, field
from functools import cached_property

from breadbox.types.address16 import Address16
from breadbox.types.device import Device
from breadbox.types.on_off import OnOff

UART_TYPES = {
    "w65c51n": "w65c51n",
    "um6551": "generic",
    "r6551": "generic",
    "generic": "generic",
}
"""
Mapping of the configuration `type` value to the driver backend to use.
"""

BAUD_RATES: dict[int, int] = {
    1200: 0x08,
    2400: 0x0A,
    3600: 0x0B,
    4800: 0x0C,
    7200: 0x0D,
    9600: 0x0E,
    19200: 0x0F,
}


@dataclass(kw_only=True)
class Uart6551Device(Device):
    """
    ACIA 6551 UART controller.

    Supports multiple chip variants (W65C51N, UM6551, etc.) with a
    configurable baud rate and optional RTS flow control pin.
    """

    type: str = field(default="generic")
    address: Address16
    baudrate: int = field(default=19200)
    irq: OnOff = field(default=OnOff("on"))

    def __post_init__(self) -> None:
        super().__post_init__()
        self.type = self.type.lower()
        if self.type not in UART_TYPES:
            raise ValueError(f"Invalid UART type {self.type!r} (expected one of: {', '.join(UART_TYPES)})")
        if self.baudrate not in BAUD_RATES:
            supported = ", ".join(str(b) for b in sorted(BAUD_RATES))
            raise ValueError(f"Unsupported baud rate {self.baudrate} (expected one of: {supported})")

    @cached_property
    def baud_code(self) -> int:
        """
        The 4-bit baud rate selector for the ACIA control register.
        """
        return BAUD_RATES[self.baudrate]

    @cached_property
    def pin_rts(self) -> Device | None:
        """
        The RTS flow control GPIO pin sub-device, or None.
        """
        for d in self.devices:
            if str(d.id) == "PIN_RTS":
                return d
        return None
