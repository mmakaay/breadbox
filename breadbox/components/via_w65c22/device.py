from dataclasses import dataclass
from typing import ClassVar

from breadbox.types.address16 import Address16
from breadbox.types.device import Device


PORTS = {
    "A": ["PA0", "PA1", "PA2", "PA3", "PA4", "PA5", "PA6", "PA7"],
    "B": ["PB0", "PB1", "PB2", "PB3", "PB4", "PB5", "PB6", "PB7"],
}

PINS = {pin: port for port, pins in PORTS.items() for pin in pins}


@dataclass(kw_only=True)
class ViaW65c22Device(Device):
    component_type: ClassVar[str] = "via_w65c22"
    address: Address16

    def get_port(self, port: str) -> list[str]:
        try:
            return PORTS[port.upper()]
        except KeyError:
            raise ValueError(f"Port {port!r} does not exist")


class ViaW65c22PortPin(str):
    def __new__(cls, value: object) -> "ViaW65c22PortPin":
        if isinstance(value, cls):
            return value
        if not isinstance(value, str):
            raise ValueError(f"Expected a string, got {type(value).__name__!r}")
        value = value.upper()
        if value not in PINS:
            raise ValueError(f"{value!r} is not a valid W65C22 port pin (expected one of: {', '.join(sorted(PINS))})")
        return super().__new__(cls, value)

    def __repr__(self) -> str:
        return str(self)


class ViaW65c22Port(str):
    def __new__(cls, value: object) -> "ViaW65c22Port":
        if isinstance(value, cls):
            return value
        if not isinstance(value, str):
            raise ValueError(f"Expected a string, got {type(value).__name__!r}")
        value = value.upper()
        if value not in PORTS:
            raise ValueError(f"{value!r} is not a valid W65C22 port (expected one of: {', '.join(sorted(PORTS))})")
        return super().__new__(cls, value)

    def __repr__(self) -> str:
        return str(self)
