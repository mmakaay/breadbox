from __future__ import annotations

from dataclasses import dataclass, field
from functools import cached_property
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
    clock_hz: int = field(default=0, init=False)

    def __post_init__(self) -> None:
        super().__post_init__()

        self.characters = self.characters.lower().replace(" ", "")
        if self.characters not in ("5x8", "5x10"):
            raise ValueError(f"Invalid character_set {self.characters!r} (expected '5x8' or '5x10')")

        if self.mode not in ("4bit", "8bit"):
            raise ValueError(f"Invalid mode {self.mode!r} (expected '4bit' or '8bit')")

        if self.height not in (1, 2, 4):
            raise ValueError(f"Invalid height {self.height} (expected 1, 2 or 4)")

        if self.width < 1:
            raise ValueError(f"Invalid width {self.width} (must be >= 1)")

        byte_size = self.width * self.height
        if byte_size > 80:
            raise ValueError(f"Invalid width x height (requires {byte_size} bytes, but device has 80 bytes)")

    @cached_property
    def ctrl(self) -> Device:
        """
        The CTRL (RS + RWB) control pin group sub-device.
        """
        return self._sub("CTRL")

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
    def funcset_value(self) -> int:
        """
        "Function Set" command byte, computed from mode/height/characters.

        This is an init-only command (cannot be changed after power-up).
        """
        val = 0x20  # CMD_FUNCSET base
        if self.mode == "8bit":
            val |= 0x10  # DL: 8-bit data bus
        if self.height >= 2:
            val |= 0x08  # N: multi-line mode (2+ rows)
        if self.characters == "5x10":
            val |= 0x04  # F: 5x10 font
        return val

    @cached_property
    def row_offsets(self) -> list[int]:
        """
        DDRAM start addresses for each display row.

        The HD44780 maps two logical lines at $00 and $40. Four-row
        displays wrap into the continuation area of each logical line.
        """
        base = [0x00, 0x40, self.width, 0x40 + self.width]
        return base[: self.height]
