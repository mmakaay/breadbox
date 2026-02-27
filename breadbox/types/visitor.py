from __future__ import annotations

from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    from breadbox.types.component import Component


class ComponentVisitor(Protocol):
    def visit(self, component: Component) -> None: ...
