from dataclasses import dataclass

from breadbox.types.address16 import Address16
from breadbox.types.device import Device


PORTS = {
    "A": ["PA0", "PA1", "PA2", "PA3", "PA4", "PA5", "PA6", "PA7"],
    "B": ["PB0", "PB1", "PB2", "PB3", "PB4", "PB5", "PB6", "PB7"],
}

PINS = {pin: port for port, pins in PORTS.items() for pin in pins}


@dataclass(kw_only=True)
class ViaW65c22Device(Device):
    address: Address16

    def get_port(self, port: str) -> list[str]:
        try:
            return PORTS[port.upper()]
        except KeyError:
            raise ValueError(f"Port {port!r} does not exist")

    def resolve_pins(self, pin_names: list[str]) -> tuple[str, int]:
        """Validate that all pins belong to the same port.

        Returns (port_name, bitmask) derived from the pin positions.
        """
        ports = set()
        for pin in pin_names:
            normalized = pin.upper()
            if normalized not in PINS:
                raise ValueError(f"{pin!r} is not a valid pin")
            ports.add(PINS[normalized])
        if len(ports) != 1:
            raise ValueError(
                f"All pins must be on the same port, got pins from ports: {', '.join(sorted(ports))}"
            )
        port = ports.pop()
        port_pins = PORTS[port]
        bitmask = sum(1 << port_pins.index(pin.upper()) for pin in pin_names)
        return port, bitmask


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
