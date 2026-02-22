from typing import Literal

from pydantic import BaseModel

from breadbox.types.device_identifier import DeviceIdentifier


class GpioPinSettings(BaseModel):
    bus: DeviceIdentifier
    direction: Literal["out", "in", "both"] = "both"
    default: Literal["on", "off"] = "off"
