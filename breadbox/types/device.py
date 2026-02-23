from abc import ABC
from functools import cached_property
from typing import Self, Any

from pydantic import BaseModel, Field

from breadbox.types.device_identifier import DeviceIdentifier


class Device[TSettings: BaseModel](ABC, BaseModel):
    id: DeviceIdentifier
    component_type: str
    settings: TSettings

    parent: "Device[Any] | None" = None
    """
    The parent Device that contains this Device.
    """

    def get_sub_devices(self) -> list["Device[Any]"]:
        """
        Returns the sub-devices, contained by this Device.

        This must be overridden in Device classes that make use of sub-devices.
        """
        return []

    @cached_property
    def device_path(self) -> str:
        device = self
        path = [self.id]
        while device.parent:
            device = device.parent
            path.insert(0, device.id)
        return "::".join(path)

    def get_info(self) -> dict[str, str]:
        return {k: str(v) for k, v in self.settings.model_dump().items()}
