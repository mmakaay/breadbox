import importlib
from typing import Any

from breadbox.components.gpio_pin.abstract_gpio_pin_device import AbstractGpioPinDevice
from breadbox.components.gpio_pin.settings import GpioPinSettings
from breadbox.config import BreadboxConfig


def resolve(config: BreadboxConfig, device_settings: dict[str, Any]) -> AbstractGpioPinDevice:
    settings = GpioPinSettings.model_validate(device_settings)
    bus_device = config.get(settings.bus)

    bus_type = bus_device.component_type
    module_name = f"breadbox.components.{bus_type}.gpio_pin.component"
    try:
        module = importlib.import_module(module_name)
    except ModuleNotFoundError:
        raise ValueError(f"Bus type {bus_type!r} does not support gpio_pin (no module {module_name})")

    return module.resolve(config, bus_device, device_settings)
