from __future__ import annotations

from abc import ABC
from functools import cached_property
from typing import TYPE_CHECKING

from pydantic import BaseModel, ConfigDict, PrivateAttr

from breadbox.types.device_identifier import DeviceIdentifier

if TYPE_CHECKING:
    from breadbox.visitor import DeviceVisitor


class Device(ABC, BaseModel):
    model_config = ConfigDict(ignored_types=(cached_property,), arbitrary_types_allowed=True)

    id: DeviceIdentifier
    component_type: str
    parent: Device | None = None

    _internal_fields: set[str] = {"id", "component_type", "parent"}
    _devices: list[Device] = PrivateAttr(default_factory=list)

    @property
    def devices(self) -> list[Device]:
        return self._devices

    def add(self, device: Device) -> None:
        device.parent = self
        self._devices.append(device)

    @cached_property
    def device_path(self) -> str:
        device: Device = self
        path = [self.id]
        while device.parent:
            device = device.parent
            path.insert(0, device.id)
        return "::".join(path)

    def accept(self, visitor: DeviceVisitor) -> None:
        visitor.visit(self)
