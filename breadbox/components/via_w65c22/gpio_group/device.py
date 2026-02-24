from dataclasses import dataclass
from typing import ClassVar

from breadbox.components.via_w65c22.device import ViaW65c22Device, ViaW65c22Port, ViaW65c22PortPin
from breadbox.types.device import Device
from breadbox.types.on_off import OnOff
from breadbox.types.pin_direction import PinDirection


@dataclass(kw_only=True)
class ViaW65c22GpioGroupDevice(Device):
    component_type: ClassVar[str] = "via_w65c22"
    bus_device: ViaW65c22Device
    pins: list[ViaW65c22PortPin]
    bitmask: int
    port: ViaW65c22Port
    bus: str
    direction: PinDirection = PinDirection("both")
    default: OnOff = OnOff("off")

    _internal_fields: ClassVar[set[str]] = {"id", "parent", "bus_device", "bus"}

    def __post_init__(self) -> None:
        super().__post_init__()
        self.pins = [ViaW65c22PortPin(p) for p in self.pins]
