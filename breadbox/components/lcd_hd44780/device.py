from __future__ import annotations

from typing import Literal

from pydantic import BaseModel

from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


class CmndSettings(BaseModel):
    bus: DeviceIdentifier
    rwb_pin: str
    en_pin: str
    rs_pin: str


class DataSettings(BaseModel):
    bus: DeviceIdentifier
    mode: Literal["4bit", "8bit"]
    port: str


class LcdHd44780Device(Device):
    component_type: str = "lcd_hd44780"
    cmnd: CmndSettings
    data: DataSettings
