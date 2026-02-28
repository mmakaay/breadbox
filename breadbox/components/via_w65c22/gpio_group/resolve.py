from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_group.device import ViaW65c22GpioGroupDevice
from breadbox.config import BreadboxConfig
from breadbox.types.bits import Bits
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    bus_device: ViaW65c22Device,
    device_settings: dict[str, Any],
) -> Component:
    has_port_bits = "port" in device_settings and "bits" in device_settings
    has_pins = "pins" in device_settings

    if has_pins and not has_port_bits:
        # pins config: derive port + bits from pin names via the bus device.
        # Pin ordering is preserved as given by the caller — consumers may
        # assign semantic meaning to positions (e.g. LCD: [RS, RWB]).
        port, bitmask = bus_device.resolve_pins(device_settings["pins"])
        bits = Bits(bitmask)
        pins = [p.upper() for p in device_settings["pins"]]

        device_settings["pins"] = pins
        device_settings["bits"] = bits
        device_settings["port"] = port

    elif has_port_bits and not has_pins:
        # port + bits config: derive pins from the bitmask.
        bits = Bits(device_settings["bits"])
        pins_for_port = bus_device.get_port(device_settings["port"])
        pins = [pins_for_port[i] for i in bits.positions]

        device_settings["bits"] = bits
        device_settings["pins"] = pins

    else:
        raise ValueError(
            f"Configuration for {component_id!r} requires either 'port' + 'bits' or 'pins' (not both)"
        )

    return ViaW65c22GpioGroupDevice(id=component_id, bus_device=bus_device, **device_settings)
