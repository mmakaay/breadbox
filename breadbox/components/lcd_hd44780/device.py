from __future__ import annotations

from dataclasses import dataclass
from functools import cached_property

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
    """
    HD44780 LCD display controller.

    Manages sub-devices for control pins (RS, RWB, EN) and data bus (DATA).
    Supports both 4-bit and 8-bit data bus modes.
    """

    mode: str

    def __post_init__(self) -> None:
        super().__post_init__()
        if self.mode not in ("4bit", "8bit"):
            raise ValueError(f"Invalid mode {self.mode!r} (expected '4bit' or '8bit')")

    @cached_property
    def pin_rs(self) -> Device:
        """
        The RS (Register Select) control pin sub-device.
        """
        return self._sub("PIN_RS")

    @cached_property
    def pin_rwb(self) -> Device:
        """
        The RWB (Read/Write) control pin sub-device.
        """
        return self._sub("PIN_RWB")

    @cached_property
    def pin_en(self) -> Device:
        """
        The EN (Enable) control pin sub-device.
        """
        return self._sub("PIN_EN")

    @cached_property
    def data(self) -> Device:
        """
        The DATA bus sub-device (gpio_group).
        """
        return self._sub("DATA")

    def _sub(self, name: str) -> Device:
        """
        Look up a sub-device by its device ID.
        """
        for d in self.devices:
            if str(d.id) == name:
                return d
        raise ValueError(f"Sub-device {name!r} not found on {self.id!r}")

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
