from typing import Self


class MemorySize(int):
    """
    Memory region size in bytes, with human-readable display.

    Accepts integers and $xxxx / 0xxxx hex strings (like Address16).
    Displays as e.g. "16384 ($4000, 16 kB)".
    """

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
            raise ValueError(f"Cannot parse memory size from {type(value).__name__!r}")
        if parsed < 0:
            raise ValueError(f"Memory size cannot be negative: {parsed}")
        if parsed > 0x10000:
            raise ValueError(f"Memory size {parsed:#x} exceeds 16-bit address space")
        return super().__new__(cls, parsed)

    def __str__(self) -> str:
        return f"{int(self)} (${self:04X}, {self._human_readable()})"

    def __repr__(self) -> str:
        return f"MemorySize(${self:04X})"

    def _human_readable(self) -> str:
        n = int(self)
        if n == 0:
            return "0 B"
        if n < 1024:
            return f"{n} B"
        kb = n / 1024
        if kb == int(kb):
            return f"{int(kb)} kB"
        return f"{kb:.1f} kB"
