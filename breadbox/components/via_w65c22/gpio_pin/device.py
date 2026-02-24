from dataclasses import dataclass, field
from functools import cached_property

from breadbox.components.via_w65c22.device import PINS, PORTS, ViaW65c22Device, ViaW65c22PortPin
from breadbox.types.device import Device
from breadbox.types.on_off import OnOff
from breadbox.types.pin_direction import PinDirection


@dataclass(kw_only=True)
class ViaW65c22GpioPinDevice(Device):
    bus_device: ViaW65c22Device
    pin: ViaW65c22PortPin
    bus: str
    direction: PinDirection = field(default=PinDirection("both"))
    default: OnOff = field(default=OnOff("off"))

    def __post_init__(self) -> None:
        super().__post_init__()
        self._internal_fields.add("bus_device")

    @cached_property
    def port(self) -> str:
        """
        The VIA port this pin belongs to ("A" or "B").
        """
        return PINS[str(self.pin)]

    @cached_property
    def bitmask(self) -> int:
        """
        Single-bit mask for this pin's position on its port.
        """
        port_pins = PORTS[self.port]
        return 1 << port_pins.index(str(self.pin))

    @cached_property
    def exclusive_port(self) -> bool:
        """
        True when this pin is the sole device on its VIA port.
        """
        return self.bus_device.is_port_exclusive(self)
