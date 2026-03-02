from __future__ import annotations

import dataclasses
import inspect
from abc import ABC
from functools import cached_property
from pathlib import Path
from typing import TYPE_CHECKING, ClassVar, get_origin, get_type_hints

from breadbox.types.component_identifier import ComponentIdentifier

if TYPE_CHECKING:
    from breadbox.types.visitor import ComponentVisitor


@dataclasses.dataclass(kw_only=True)
class Component(ABC):
    id: ComponentIdentifier
    _COMPONENTS_PREFIX: ClassVar[str] = "breadbox.components."
    parent: Component | None = dataclasses.field(default=None, repr=False)

    _internal_fields: ClassVar[set[str]] = {"id", "parent"}

    @property
    def component_type(self) -> str:
        """
        Derived from the module path: breadbox.components.{type}[.sub].device
        """
        return type(self).__module__.removeprefix(self._COMPONENTS_PREFIX).split(".")[0]

    @cached_property
    def component_dir(self) -> Path:
        """
        Absolute path to the component package that defines this component.

        Derived via inspect from the module where the component class lives.
        For example, ViaW65c22GpioPinDevice -> .../components/via_w65c22/gpio_pin/
        """
        return Path(inspect.getfile(type(self))).parent

    @cached_property
    def source_path(self) -> Path:
        """
        Component path relative to the components root.

        Used by the code generator to locate src/ templates and
        determine the output subdirectory.
        For example, ViaW65c22GpioPinDevice -> Path("via_w65c22/gpio_pin")
        """
        components_root = Path(__file__).parent.parent / "components"
        return self.component_dir.relative_to(components_root)

    def __post_init__(self) -> None:
        self._children: list[Component] = []
        self._coerce_fields()

    def _coerce_fields(self) -> None:
        """
        Auto-coerce scalar fields whose declared type is a custom str/int subclass.

        This allows raw YAML values (plain strings/ints) to be automatically
        validated and converted to their declared types (ComponentIdentifier,
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
    def children(self) -> list[Component]:
        return self._children

    def add(self, child: Component) -> None:
        child.parent = self
        self._children.append(child)

    def make_path(self, separator: str) -> str:
        component: Component = self
        path = [self.id]
        while component.parent:
            component = component.parent
            path.insert(0, component.id)
        return separator.join(path)

    @cached_property
    def component_path(self) -> Path:
        return Path(self.make_path("/"))

    @cached_property
    def symbol_prefix(self) -> str:
        return self.make_path("_")

    @cached_property
    def scope(self) -> str:
        return self.make_path("_")

    def api(self, name: str) -> str:
        """Reference a public API subroutine: __{scope}_{name}."""
        return f"__{self.scope}_{name}"

    def accept(self, visitor: ComponentVisitor) -> None:
        visitor.visit(self)
