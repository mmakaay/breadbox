#from abc import ABC, abstractmethod

from abc import abstractmethod, ABC
from typing import Any

from pydantic import BaseModel

from breadbox.components.gpio_pin.abstract_gpio_pin_device import AbstractGpioPinDevice
from breadbox.config import BreadboxConfig


class AbstractGpioPinBus(ABC, BaseModel):
    """
    Abstract base class, to be implemented by bus devices that can provide a GPIO pin device.
    """
    @abstractmethod
    def resolve_gpio_pin(self, config: BreadboxConfig, device_settings: dict[str, Any]) -> AbstractGpioPinDevice:
        """
        Performs additional config resolving when creating a GPIO pin device.

        The GPIO pin that is configured, gets a `bus` device identifier, which
        points as the bus device that is used to implement the GPIO pin. That
        bus device must implement this method to perform any additional pin
        configuration resolving, on top of what has already been done by the
        GpioPinComponent.

        The return value is a component object that is passed back to the
        GpioPinComponent, and which will be used by that component to generate
        the code for driving the pin.
        """
        raise NotImplementedError
