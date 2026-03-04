from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from breadbox.types.component import Component


class ClientCollector:
    """
    Walk the component tree and register clients on their provider devices.

    Each component that holds a provider_device reference is registered on that
    provider device via register_client(). The provider device itself decides
    how to use this information (e.g. the W65C22 VIA uses it to
    determine port exclusivity).
    """

    def visit(self, component: Component) -> None:
        """
        Register this component as a client and recurse into children.
        """
        from breadbox.types.device import Device

        provider_device = getattr(component, "provider_device", None)
        if provider_device is not None and isinstance(component, Device):
            provider_device.register_client(component)

        for sub in component.children:
            sub.accept(self)
