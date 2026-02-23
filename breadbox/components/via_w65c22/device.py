from typing import Any

import pydantic
from pydantic_core import core_schema

from breadbox.components.via_w65c22.settings import ViaW65c22Settings
from breadbox.types.device import Device


PORTS = {
    "A": ["PA0", "PA1", "PA2", "PA3", "PA4", "PA5", "PA6", "PA7"],
    "B": ["PB0", "PB1", "PB2", "PB3", "PB4", "PB5", "PB6", "PB7"],
}

PINS = {
    pin: port
    for port, pins in PORTS.items()
    for pin in pins
}


class ViaW65c22Device(Device):
    component_type: str = "via_w65c22"
    settings: ViaW65c22Settings

    def get_info(self) -> dict[str, str]:
        return {
            "address": str(self.settings.address),
        }

    def get_port(self, port: str) -> list[str]:
        try:
            return PORTS[port.upper()]
        except KeyError:
            raise ValueError(f"Port {port!r} does not exist")


class ViaW65c22PortPin(str):
    """Port pin identifier: PA0-PA7 or PB0-PB7 (case-insensitive, stored uppercase)."""

    @classmethod
    def __get_pydantic_core_schema__(cls, source_type: Any, handler):
        return core_schema.no_info_plain_validator_function(cls._validate)

    @classmethod
    def _validate(cls, value: Any) -> "ViaW65c22PortPin":
        if not isinstance(value, str):
            raise ValueError(f"Expected a string, got {type(value).__name__!r}")
        value = value.upper()
        if not value in PINS:
            raise ValueError(
                f"{value!r} is not a valid W65C22 port pin (expected one of: "
                f"{', '.join(sorted(PINS))})")
        return cls(value)

    def __repr__(self) -> str:
        return f"ViaW65c22PortPin({str(self)!r})"


class ViaW65c22Port(str):

    @classmethod
    def __get_pydantic_core_schema__(cls, source_type: Any, handler):
        return core_schema.no_info_plain_validator_function(cls._validate)

    @classmethod
    def _validate(cls, value: Any) -> "ViaW65c22Port":
        if not isinstance(value, str):
            raise ValueError(f"Expected a string, got {type(value).__name__!r}")
        value = value.upper()
        if not value in PORTS:
            raise ValueError(
                f"{value!r} is not a valid W65C22 port (expected one of: "
                f"{', '.join(sorted(PORTS))})")
        return cls(value)

    def __repr__(self) -> str:
        return f"ViaW65c22Port({str(self)!r})"
