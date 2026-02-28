from dataclasses import dataclass, field
from functools import cached_property

from breadbox.components.via_w65c22.device import ViaW65c22Device, ViaW65c22Port, ViaW65c22PortPin
from breadbox.types.bits import Bits
from breadbox.types.device import Device
from breadbox.types.on_off import OnOff
from breadbox.types.pin_direction import PinDirection


@dataclass(kw_only=True)
class ViaW65c22GpioGroupDevice(Device):
    bus_device: ViaW65c22Device
    pins: list[ViaW65c22PortPin]
    bits: Bits
    port: ViaW65c22Port
    bus: str
    direction: PinDirection = field(default=PinDirection("both"))
    default: OnOff | None = None

    def __post_init__(self) -> None:
        super().__post_init__()
        self._internal_fields.add("bus_device")
        self.pins = [ViaW65c22PortPin(p) for p in self.pins]
        if self.default is not None:
            self.default = OnOff(self.default)
        if self.direction == "in" and self.default is not None:
            raise ValueError(
                f"Device {self.id!r}: default value is not allowed for direction 'in'"
            )

    @cached_property
    def exclusive_port(self) -> bool:
        """
        True when this group is the sole device on its VIA port.
        """
        return self.bus_device.is_port_exclusive(self)

    def pin_bit(self, pin_name: str) -> int:
        """
        Bitmask for a single pin within this group's port register.
        """
        port_pins = self.bus_device.get_port(str(self.port))
        try:
            return 1 << port_pins.index(pin_name.upper())
        except ValueError:
            raise ValueError(
                f"Pin {pin_name!r} is not part of group {self.id!r}"
                f" (available: {', '.join(str(p) for p in self.pins)})"
            ) from None

    @cached_property
    def pin_bitmasks(self) -> list[int]:
        """
        Bitmask for each pin, in the same order as self.pins.
        """
        port_pins = self.bus_device.get_port(str(self.port))
        return [1 << port_pins.index(str(p)) for p in self.pins]
