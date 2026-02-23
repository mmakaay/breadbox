from breadbox.types.device import Device


class AbstractGpioPinDevice(Device):

    def get_info(self) -> dict[str, str]:
        return {
            "implementation": str(self.__class__.__name__),
            "bus": self.settings.bus,
            "direction": self.settings.direction,
            "default": self.settings.default,
        }
