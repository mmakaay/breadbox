from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from breadbox.types.device import Device


class BusClientCollector:
    """
    Walk the device tree and register bus clients on their bus devices.

    Each device that holds a bus_device reference is registered on that
    bus device via register_bus_client(). The bus device itself decides
    how to use this information (e.g. the W65C22 VIA uses it to
    determine port exclusivity).
    """

    def visit(self, device: Device) -> None:
        """
        Register this device as a bus client and recurse into sub-devices.
        """
        bus_device = getattr(device, "bus_device", None)
        if bus_device is not None:
            bus_device.register_bus_client(device)

        for sub in device.devices:
            sub.accept(self)
