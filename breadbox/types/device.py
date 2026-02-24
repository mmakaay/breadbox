from __future__ import annotations

import dataclasses
from abc import ABC
from functools import cached_property
from typing import TYPE_CHECKING, ClassVar, get_origin, get_type_hints

from breadbox.types.device_identifier import DeviceIdentifier

if TYPE_CHECKING:
    from breadbox.visitor import DeviceVisitor


@dataclasses.dataclass(kw_only=True)
class Device(ABC):
    id: DeviceIdentifier
    _COMPONENTS_PREFIX: ClassVar[str] = "breadbox.components."
    parent: Device | None = dataclasses.field(default=None, repr=False)

    _internal_fields: ClassVar[set[str]] = {"id", "parent"}

    @property
    def component_type(self) -> str:
        """
        Derived from the module path: breadbox.components.{type}[.sub].device
        """
        return type(self).__module__.removeprefix(self._COMPONENTS_PREFIX).split(".")[0]

    def __post_init__(self) -> None:
        self._devices: list[Device] = []
        self._coerce_fields()

    def _coerce_fields(self) -> None:
        """
        Auto-coerce scalar fields whose declared type is a custom str/int subclass.

        This allows raw YAML values (plain strings/ints) to be automatically
        validated and converted to their declared types (DeviceIdentifier,
        Address16, PinDirection, OnOff, etc.) without manual coercion in
        every component resolver.
        """
        hints = get_type_hints(type(self))
        for f in dataclasses.fields(self):
            hint = hints.get(f.name)
            if hint is None or get_origin(hint) is not None:
                continue
            if not isinstance(hint, type) or hint in (str, int, float, bool) or not issubclass(hint, (str, int)):
                continue
            value = getattr(self, f.name)
            if value is not None and not isinstance(value, hint):
                setattr(self, f.name, hint(value))

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
