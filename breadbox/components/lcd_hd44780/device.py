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
    def validate_pins(self) -> None:
        """
        Verify that no physical pin is used by more than one sub-device.
        """
        seen: set[tuple[str, str]] = set()
        for sub in self.devices:
            bus = getattr(sub, "bus", None)
            if bus is None:
                continue
            for pin in self._pins_of(sub):
                key = (str(bus), str(pin).upper())
                if key in seen:
                    raise ValueError(f"Duplicate pin assignment: {key[1]} on {key[0]}")
                seen.add(key)

    @staticmethod
    def _pins_of(sub: Device) -> list[str]:
        """
        Extract pin name(s) from a gpio_pin or gpio_group sub-device.
        """
        pin = getattr(sub, "pin", None)
        if pin is not None:
            return [str(pin)]
        pins = getattr(sub, "pins", None)
        if pins is not None:
            return [str(p) for p in pins]
        return []
