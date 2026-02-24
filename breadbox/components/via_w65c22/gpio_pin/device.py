from breadbox.components.via_w65c22.device import ViaW65c22Device, ViaW65c22PortPin
from breadbox.types.device import Device
from breadbox.types.on_off import OnOff
from breadbox.types.pin_direction import PinDirection


class ViaW65c22GpioPinDevice(Device):
    component_type: str = "via_w65c22"
    bus_device: ViaW65c22Device
    pin: ViaW65c22PortPin
    bus: str
    direction: PinDirection = PinDirection("both")
    default: OnOff = "off"

    _internal_fields: set[str] = {"id", "component_type", "parent", "bus_device", "bus"}
