from breadbox.components.gpio_pin.settings import GpioPinSettings
from breadbox.components.via_w65c22.device import ViaW65c22Device, ViaW65c22Port, ViaW65c22PortPin


class ViaW65c22GpioGroupSettings(GpioPinSettings):
    bus_device: ViaW65c22Device
    pins: list[ViaW65c22PortPin]
    bitmask: int
    port: ViaW65c22Port
