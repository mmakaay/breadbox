from __future__ import annotations

import dataclasses

from breadbox.types.component import Component


@dataclasses.dataclass(kw_only=True)
class Device(Component):
    """
    A hardware device component.

    Adds bus client registration and validation for hardware-specific
    concerns like pin conflicts.
    """

    def register_bus_client(self, device: Device) -> None:  # noqa: B027
        """
        Called when a device declares this device as its bus.

        Override in bus device subclasses to track clients.
        The default implementation is a no-op.
        """

    def validate_bus_clients(self) -> None:  # noqa: B027
        """
        Validate registered bus clients for conflicts.

        Override in bus device subclasses to check for
        pin conflicts, etc. The default implementation is a no-op.
        """
