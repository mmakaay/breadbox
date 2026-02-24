from typing import Self


class Address16(int):
    """16-bit memory address, accepting $xxxx or 0xxxxx hex notation."""

    def __new__(cls, value: object) -> Self:
        if isinstance(value, cls):
            return value
        if isinstance(value, int):
            parsed = value
        elif isinstance(value, str):
            normalized = value.strip()
            if normalized.startswith("$"):
                normalized = "0x" + normalized[1:]
            parsed = int(normalized, 0)
        else:
            raise ValueError(f"Cannot parse address from {type(value).__name__!r}")
        if not (0x0000 <= parsed <= 0xFFFF):
            raise ValueError(f"Address {parsed:#06x} out of 16-bit range")
        return super().__new__(cls, parsed)

    def __str__(self) -> str:
        return f"${self:04X}"

    def __repr__(self) -> str:
        return f"Address16(${self:04X})"
