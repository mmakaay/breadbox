from breadbox.components.gpio_pin.abstract_gpio_pin_device import AbstractGpioPinDevice
from breadbox.components.via_w65c22.gpio_pin.settings import ViaW65c22GpioPinSettings


class ViaW65c22GpioPinDevice(AbstractGpioPinDevice):
    settings: ViaW65c22GpioPinSettings

    def get_info(self) -> dict[str, str]:
        return {
            "key": "value",
        }
