from __future__ import annotations

import dataclasses

from breadbox.types.component import Component


@dataclasses.dataclass(kw_only=True)
class Device(Component):
    """
    A hardware device component.

    Adds client registration and validation for hardware-specific
    concerns like pin conflicts.
    """

    def register_client(self, device: Device) -> None:
        """
        Called when a device declares this device as its provider.

        Override in provider device subclasses to track clients.
        The default implementation is a no-op.
        """

    def validate_clients(self) -> None:
        """
        Validate registered clients for conflicts.

        Override in provider device subclasses to check for
        pin conflicts, etc. The default implementation is a no-op.
        """

    def _sub(self, name: str) -> Device:
        """
        Look up a child device by its ID.
        """
        for d in self.children:
            if isinstance(d, Device) and str(d.id) == name:
                return d
        raise ValueError(f"Child device {name!r} not found on {self.id!r}")
