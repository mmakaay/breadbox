from typing import Literal

from pydantic import BaseModel

from breadbox.types.device_identifier import DeviceIdentifier
from breadbox.types.on_off import OnOff


class GpioGroupSettings(BaseModel):
    """
    Base settings that apply to all GPIO pin groups.

    Additional values (like the actual pin names, which are specific to the pin naming
    as used for the bus device in use) are to be handled by the bus device implementation.
    """
    bus: DeviceIdentifier
    direction: Literal["out", "in", "both"] = "both"
    default: OnOff = "off"
