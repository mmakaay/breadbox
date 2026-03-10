from __future__ import annotations

from dataclasses import dataclass

from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier
from breadbox.types.device import Device


@dataclass(kw_only=True)
class TtyDevice(Device):
    """
    TTY device.

    Provides a device that implements an abstraction layer on top of terminal
    device. It implements some of the typical TTY functionalities, like line
    discipline for standard terminal use, and input buffering.

    The device must be linked to an input device, and an output device.
    Together, these form the standard input and output of the system.
    The input device is used by the end user to enter data (e.g. a keyboard or
    typing over an RS232 connection). The output device is used to present output
    to the end-user (e.g. an RS232 connection or an LCD).
    """
    input: ComponentIdentifier
    input_device: Component

    output: ComponentIdentifier
    output_device: Component

    def __post_init__(self) -> None:
        super().__post_init__()
        self._internal_fields.add("input_device")
        self._internal_fields.add("output_device")
