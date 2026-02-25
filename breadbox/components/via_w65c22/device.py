import dataclasses
from dataclasses import dataclass
from typing import Self

from breadbox.types.address16 import Address16
from breadbox.types.device import Device

PORTS = {
    "A": ["PA0", "PA1", "PA2", "PA3", "PA4", "PA5", "PA6", "PA7"],
    "B": ["PB0", "PB1", "PB2", "PB3", "PB4", "PB5", "PB6", "PB7"],
}

PINS = {pin: port for port, pins in PORTS.items() for pin in pins}

REGISTERS = [
    ("PORTB", 0x00),
    ("PORTA", 0x01),
    ("DDRB", 0x02),
    ("DDRA", 0x03),
    ("T1CL", 0x04),
    ("T1CH", 0x05),
    ("T1LL", 0x06),
    ("T1LH", 0x07),
    ("T2CL", 0x08),
    ("T2CH", 0x09),
    ("SR", 0x0A),
    ("ACR", 0x0B),
    ("PCR", 0x0C),
    ("IFR", 0x0D),
    ("IER", 0x0E),
    ("PORTA_NH", 0x0F),
]


@dataclass(kw_only=True)
class ViaW65c22Device(Device):
    address: Address16
    _bus_clients: list[Device] = dataclasses.field(default_factory=list, init=False, repr=False)

    def __post_init__(self) -> None:
        super().__post_init__()
        self._internal_fields.add("_bus_clients")

    @property
    def registers(self) -> list[tuple[str, int]]:
        return REGISTERS

    def register_bus_client(self, device: Device) -> None:
        """
        Track a device that uses this VIA as its bus.
        """
        self._bus_clients.append(device)

    def is_port_exclusive(self, device: Device) -> bool:
        """
        Check whether a device is the sole client on its VIA port.

        Returns True if no other registered bus client shares the
        same port. Devices without a port attribute are always
        considered exclusive.
        """
        port = getattr(device, "port", None)
        if port is None:
            return True
        return sum(1 for c in self._bus_clients if getattr(c, "port", None) == port) <= 1

    def validate_bus_clients(self) -> None:
        """
        Check that no physical pin is claimed by multiple bus clients.
        """
        pin_owners: dict[str, Device] = {}
        for client in self._bus_clients:
            pins = self._client_pins(client)
            for pin in pins:
                if pin in pin_owners:
                    other = pin_owners[pin]
                    raise ValueError(
                        f"Pin conflict on {self.id}: pin {pin} is used by both"
                        f" {other.asm_scope!r} and {client.asm_scope!r}"
                    )
                pin_owners[pin] = client

    @staticmethod
    def _client_pins(device: Device) -> list[str]:
        """
        Extract the physical pin names claimed by a bus client.
        """
        pin = getattr(device, "pin", None)
        if pin is not None:
            return [str(pin)]
        pins = getattr(device, "pins", None)
        if pins is not None:
            return [str(p) for p in pins]
        return []

    @staticmethod
    def get_port(port: str) -> list[str]:
        try:
            return PORTS[port.upper()]
        except KeyError:
            raise ValueError(f"Port {port!r} does not exist") from None

    @staticmethod
    def resolve_pins(pin_names: list[str]) -> tuple[str, int]:
        """
        Validate that all pins belong to the same port.

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
    def __new__(cls, value: object) -> Self:
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
    def __new__(cls, value: object) -> Self:
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
