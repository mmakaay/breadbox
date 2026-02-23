from abc import ABC
from functools import cached_property
from typing import Any, Generic, TypeVar

from pydantic import BaseModel

from breadbox.types.device_identifier import DeviceIdentifier

TSettings = TypeVar("TSettings", bound=BaseModel)


class Device(ABC, BaseModel, Generic[TSettings]):
    id: DeviceIdentifier
    component_type: str
    settings: TSettings

    parent: "Device | None" = None
    """
    The parent Device that contains this Device.
    """

    def get_sub_devices(self) -> list["Device"]:
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
