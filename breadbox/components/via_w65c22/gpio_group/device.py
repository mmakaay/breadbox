from dataclasses import dataclass, field

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
    default: OnOff = field(default=OnOff("off"))

    def __post_init__(self) -> None:
        super().__post_init__()
        self._internal_fields.add("bus_device")
        self.pins = [ViaW65c22PortPin(p) for p in self.pins]
