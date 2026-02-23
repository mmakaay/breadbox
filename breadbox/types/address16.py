from typing import Any

from pydantic import GetCoreSchemaHandler
from pydantic_core import core_schema


class Address16(int):
    """16-bit memory address, accepting $xxxx or 0xxxxx hex notation."""

    @classmethod
    def __get_pydantic_core_schema__(cls, source_type: Any, handler: GetCoreSchemaHandler):
        return core_schema.no_info_plain_validator_function(
            cls._validate,
            serialization=core_schema.to_string_ser_schema(),
        )

    @classmethod
    def _validate(cls, value: Any) -> "Address16":
        if isinstance(value, int):
            parsed = value
        elif isinstance(value, str):
            normalized = value.strip()
            if normalized.startswith("$"):
                normalized = "0x" + normalized[1:]
            parsed = int(normalized, 0)  # handles 0x... and plain decimal
        else:
            raise ValueError(f"Cannot parse address from {type(value).__name__!r}")

        if not (0x0000 <= parsed <= 0xFFFF):
            raise ValueError(f"Address {parsed:#06x} out of 16-bit range")

        return cls(parsed)

    def __str__(self) -> str:
        return f"${self:04X}"

    def __repr__(self) -> str:
        return f"Address16(${self:04X})"