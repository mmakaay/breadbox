from typing import Any

from breadbox.components.gpio_pin.abstract_gpio_pin_bus import AbstractGpioPinBus
from breadbox.components.gpio_pin.abstract_gpio_pin_device import AbstractGpioPinDevice
from breadbox.components.gpio_pin.settings import GpioPinSettings
from breadbox.config import BreadboxConfig


def resolve(config: BreadboxConfig, device_settings: dict[str, Any]) -> AbstractGpioPinDevice:
    # Load the main GPIO pin settings.
    settings = GpioPinSettings.model_validate(device_settings)

    # Fetch the bus device that is configured in the settings.
    bus_device = config.get(settings.bus)
    if not isinstance(bus_device, AbstractGpioPinBus):
        raise ValueError(f"Device {settings.bus!r} is not a GpioPinBusDevice")

    # Let the bus device produce the device to use.
    implementation = bus_device.resolve_gpio_pin(config, device_settings)
    return implementation
