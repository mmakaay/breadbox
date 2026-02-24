from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_group.device import ViaW65c22GpioGroupDevice
from breadbox.config import BreadboxConfig
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(
    breadbox: BreadboxConfig,
    device_id: DeviceIdentifier,
    bus_device: ViaW65c22Device,
    device_settings: dict[str, Any],
) -> Device:
    # Configuration option: port + bits
    # This is translated into the related pin names.
    if "port" in device_settings and "bits" in device_settings:
        pins = []
        bitmask = 0
        pins_for_port = bus_device.get_port(device_settings["port"])
        for bit in device_settings["bits"]:
            bit_value = int(bit)
            if bit_value < 0 or bit_value > 7:
                raise ValueError(f"Invalid bit value: {bit_value}")
            pins.append(pins_for_port[bit_value])
            bitmask += 1 << bit_value
        del device_settings["bits"]
        device_settings["bitmask"] = bitmask
        device_settings["pins"] = pins
    else:
        raise ValueError(
            f"Configuration for {device_id!r} invalid (could not determine what configuration method to use)"
        )

    return ViaW65c22GpioGroupDevice(id=device_id, bus_device=bus_device, **device_settings)
