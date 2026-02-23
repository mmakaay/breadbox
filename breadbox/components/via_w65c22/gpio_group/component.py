from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_group.device import ViaW65c22GpioGroupDevice
from breadbox.components.via_w65c22.gpio_group.settings import ViaW65c22GpioGroupSettings
from breadbox.components.via_w65c22.gpio_pin.device import ViaW65c22GpioPinDevice
from breadbox.components.via_w65c22.gpio_pin.settings import ViaW65c22GpioPinSettings
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
            if 7< bit_value < 0:
                raise ValueError(f"Invalid bit value: {bit_value}")
            pins.append(pins_for_port[bit])
            bitmask += 1 << bit
        del device_settings["bits"]
        device_settings["bitmask"] = bitmask

    # Unhandled configuration.
    else:
        raise ValueError(
            f"Configuration for {device_id!r} invalid (could not determine what configuration method to use)"
        )

    combined_settings = {**device_settings, "bus_device": bus_device, "pins": pins}
    settings = ViaW65c22GpioGroupSettings.model_validate(combined_settings, extra="forbid")
    return ViaW65c22GpioGroupDevice(id=device_id, settings=settings)
