from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_group.device import ViaW65c22GpioGroupDevice
from breadbox.config import BreadboxConfig
from breadbox.types.bits import Bits
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(
    breadbox: BreadboxConfig,
    device_id: DeviceIdentifier,
    bus_device: ViaW65c22Device,
    device_settings: dict[str, Any],
) -> Device:
    if "port" not in device_settings or "bits" not in device_settings:
        raise ValueError(f"Configuration for {device_id!r} invalid (requires 'port' and 'bits')")

    bits = Bits(device_settings["bits"])
    pins_for_port = bus_device.get_port(device_settings["port"])
    pins = [pins_for_port[i] for i in bits.positions]

    device_settings["bits"] = bits
    device_settings["pins"] = pins

    return ViaW65c22GpioGroupDevice(id=device_id, bus_device=bus_device, **device_settings)
