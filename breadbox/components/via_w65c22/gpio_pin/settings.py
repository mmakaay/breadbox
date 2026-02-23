from breadbox.components.gpio_pin.settings import GpioPinSettings
from breadbox.components.via_w65c22.device import ViaW65c22Device
import re
from typing import Any
from pydantic_core import core_schema

_PORT_PIN_RE = re.compile(r'^P[AB][0-7]$')


class ViaW65c22PortPin(str):
    """Port pin identifier: PA0-PA7 or PB0-PB7 (case-insensitive, stored uppercase)."""

    @classmethod
    def __get_pydantic_core_schema__(cls, source_type: Any, handler):
        return core_schema.no_info_plain_validator_function(cls._validate)

    @classmethod
    def _validate(cls, value: Any) -> "ViaW65c22PortPin":
        if not isinstance(value, str):
            raise ValueError(f"Expected a string, got {type(value).__name__!r}")
        upper = value.upper()
        if not _PORT_PIN_RE.match(upper):
            raise ValueError(f"{value!r} is not a valid W65C22 port pin (expected PA0-PA7 or PB0-PB7)")
        return cls(upper)

    def __repr__(self) -> str:
        return f"ViaW65c22PortPin({str(self)!r})"


class ViaW65c22GpioPinSettings(GpioPinSettings):
    bus_device: ViaW65c22Device
    pin: ViaW65c22PortPin
