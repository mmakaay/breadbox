from breadbox.components.gpio_pin.abstract_gpio_pin_device import AbstractGpioPinDevice
from breadbox.components.via_w65c22.gpio_pin.settings import ViaW65c22GpioPinSettings


class ViaW65c22GpioPinDevice(AbstractGpioPinDevice):
    component_type: str = "via_w65c22"
    settings: ViaW65c22GpioPinSettings

    def get_info(self) -> dict[str, str]:
        return {k: str(v) for k,v in self.settings.model_dump(exclude={"bus_device"}).items()}
