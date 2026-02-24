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
