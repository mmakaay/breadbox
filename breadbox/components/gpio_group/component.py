import importlib
from typing import Any

from breadbox.components.gpio_group.settings import GpioGroupSettings
from breadbox.components.gpio_pin.settings import GpioPinSettings
from breadbox.config import BreadboxConfig
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(breadbox: BreadboxConfig, device_id: DeviceIdentifier, device_settings: dict[str, Any]) -> Device:
    settings = GpioGroupSettings.model_validate(device_settings)
    bus_device = breadbox.get(settings.bus)

    bus_type = bus_device.component_type
    module_name = f"breadbox.components.{bus_type}.gpio_group.component"
    try:
        module = importlib.import_module(module_name)
    except ModuleNotFoundError:
        raise ValueError(f"Bus type {bus_type!r} does not support gpio_group (no module {module_name})") from None

    return module.resolve(breadbox, device_id, bus_device, device_settings)
