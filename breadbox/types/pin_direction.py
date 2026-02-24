from typing import Self


class PinDirection(str):
    """
    Pin data direction: in, out, or both.
    """

    def __new__(cls, value: object) -> Self:
        if isinstance(value, cls):
            return value
        if not isinstance(value, str):
            raise ValueError(f"Cannot parse direction from {type(value).__name__!r}")
        normalized = value.strip().lower()
        if normalized not in ("in", "out", "both"):
            raise ValueError(f"Invalid direction {value!r} (must be 'in', 'out' or 'both')")
        return super().__new__(cls, normalized)

    def __repr__(self) -> str:
        return f"PinDirection({self!s})"
