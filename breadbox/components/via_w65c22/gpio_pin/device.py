from breadbox.components.via_w65c22.gpio_pin.settings import ViaW65c22GpioPinSettings
from breadbox.types.device import Device


class ViaW65c22GpioPinDevice(Device):
    component_type: str = "via_w65c22"
    settings: ViaW65c22GpioPinSettings

    def get_info(self) -> dict[str, str]:
        return {k: str(v) for k,v in self.settings.model_dump(exclude={"bus_device"}).items()}
