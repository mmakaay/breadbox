from typing import Literal

from pydantic import BaseModel

from breadbox.types.device_identifier import DeviceIdentifier

class CmndSettings(BaseModel):
    bus: DeviceIdentifier
    rwb_pin: str
    en_pin: str
    rs_pin: str

class DataSettings(BaseModel):
    mode: Literal["4bit", "8bit"]
    bus: DeviceIdentifier
    pins: Literal["PA0-3", "PA4-7", "PB0-3", "PB4-7"]


class LcdHd44780Settings(BaseModel):
    cmnd: CmndSettings
    data: DataSettings
