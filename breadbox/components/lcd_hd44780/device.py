from __future__ import annotations

from dataclasses import dataclass
from functools import cached_property
from typing import cast

from breadbox.components.via_w65c22.gpio_group.device import ViaW65c22GpioGroupDevice
from breadbox.types.device import Device
from breadbox.types.component_identifier import ComponentIdentifier


@dataclass(kw_only=True)
class CmndSettings:
    bus: ComponentIdentifier
    rs_pin: str
    rwb_pin: str
    en_pin: str

    def __post_init__(self) -> None:
        if not isinstance(self.bus, ComponentIdentifier):
            self.bus = ComponentIdentifier(self.bus)


@dataclass(kw_only=True)
class DataSettings:
    bus: ComponentIdentifier
    mode: str
    port: str

    def __post_init__(self) -> None:
        if not isinstance(self.bus, ComponentIdentifier):
            self.bus = ComponentIdentifier(self.bus)
        self.mode = self.mode.lower()
        if self.mode not in ("4bit", "8bit"):
            raise ValueError(f"Invalid mode {self.mode!r} (expected '4bit' or '8bit')")


@dataclass(kw_only=True)
class LcdHd44780Device(Device):
    """
    HD44780 LCD controller.

    Manages sub-devices for control pins (CTRL group for RS+RWB, EN pin)
    and data bus (DATA). Supports both 4-bit and 8-bit data bus modes.
    """

    mode: str
    width: int = 16
    height: int = 2
    characters: str = "5x8"
    rs_pin: str
    rwb_pin: str

    def __post_init__(self) -> None:
        super().__post_init__()
        self.characters = self.characters.lower().replace(" ", "")
        if self.characters not in ("5x8", "5x10"):
            raise ValueError(f"Invalid character_set {self.characters!r} (expected '5x8' or '5x10')")

        if self.mode not in ("4bit", "8bit"):
            raise ValueError(f"Invalid mode {self.mode!r} (expected '4bit' or '8bit')")

        self.rs_pin = self.rs_pin.upper()
        self.rwb_pin = self.rwb_pin.upper()

    @cached_property
    def ctrl(self) -> ViaW65c22GpioGroupDevice:
        """
        The CTRL (RS + RWB) control pin group sub-device.
        """
        return cast(ViaW65c22GpioGroupDevice, self._sub("CTRL"))

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

    @cached_property
    def rs_bit(self) -> int:
        """
        Bitmask for the RS pin within the CTRL group.
        """
        return self._ctrl_pin_bit(self.rs_pin)

    @cached_property
    def rwb_bit(self) -> int:
        """
        Bitmask for the RWB pin within the CTRL group.
        """
        return self._ctrl_pin_bit(self.rwb_pin)

    def _ctrl_pin_bit(self, pin_name: str) -> int:
        """
        Compute the bitmask for a named pin within the CTRL group.
        """
        ctrl = self.ctrl
        port_pins = ctrl.bus_device.get_port(str(ctrl.port))
        return 1 << port_pins.index(pin_name)
    def _sub(self, name: str) -> Device:
        """
        Look up a child component by its ID.
        """
        for d in self.children:
            if isinstance(d, Device) and str(d.id) == name:
                return d
        raise ValueError(f"Child device {name!r} not found on {self.id!r}")

    def validate_pins(self) -> None:
        """
        Verify that no physical pin is used by more than one sub-device.
        """
        seen: set[tuple[str, str]] = set()
        for sub in self.children:
            if not isinstance(sub, Device):
                continue
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
