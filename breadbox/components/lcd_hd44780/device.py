from __future__ import annotations

from dataclasses import dataclass

from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


@dataclass(kw_only=True)
class CmndSettings:
    bus: DeviceIdentifier
    rwb_pin: str
    en_pin: str
    rs_pin: str

    def __post_init__(self) -> None:
        if not isinstance(self.bus, DeviceIdentifier):
            self.bus = DeviceIdentifier(self.bus)


@dataclass(kw_only=True)
class DataSettings:
    bus: DeviceIdentifier
    mode: str
    port: str

    def __post_init__(self) -> None:
        if not isinstance(self.bus, DeviceIdentifier):
            self.bus = DeviceIdentifier(self.bus)
        self.mode = self.mode.lower()
        if self.mode not in ("4bit", "8bit"):
            raise ValueError(f"Invalid mode {self.mode!r} (expected '4bit' or '8bit')")


@dataclass(kw_only=True)
class LcdHd44780Device(Device):
    pass
