from breadbox.components.via_w65c22.settings import ViaW65c22Settings
from breadbox.types.device import Device


class ViaW65c22Device(Device):
    component_type: str = "via_w65c22"
    settings: ViaW65c22Settings

    def get_info(self) -> dict[str, str]:
        return {
            "address": str(self.settings.address),
        }
