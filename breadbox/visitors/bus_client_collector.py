from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from breadbox.types.component import Component


class BusClientCollector:
    """
    Walk the component tree and register bus clients on their bus devices.

    Each component that holds a bus_device reference is registered on that
    bus device via register_bus_client(). The bus device itself decides
    how to use this information (e.g. the W65C22 VIA uses it to
    determine port exclusivity).
    """

    def visit(self, component: Component) -> None:
        """
        Register this component as a bus client and recurse into children.
        """
        from breadbox.types.device import Device

        bus_device = getattr(component, "bus_device", None)
        if bus_device is not None and isinstance(component, Device):
            bus_device.register_bus_client(component)

        for sub in component.children:
            sub.accept(self)
