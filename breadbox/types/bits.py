class Bits(int):
    """8-bit bitmask (0–255).

    Accepts multiple input formats:
        int:    255         → 0b11111111
        hex:    "$FF"       → 0b11111111
        bin:    "11000101"  → 0b11000101
        list:   [1,0,1,0,0,0,1,1]  → 0b11000101  (index 0 = bit 0)
    """

    def __new__(cls, value: object) -> "Bits":
        if isinstance(value, cls):
            return value

        if isinstance(value, list):
            if len(value) != 8 or not all(v in (0, 1) for v in value):
                raise ValueError(f"Bit list must have exactly 8 elements, each 0 or 1, got {value}")
            result = sum(bit << i for i, bit in enumerate(value))

        elif isinstance(value, str):
            stripped = value.strip()
            if stripped.startswith("$"):
                result = int(stripped[1:], 16)
            elif stripped.lower().startswith("0x"):
                result = int(stripped, 16)
            elif stripped.lower().startswith("0b"):
                result = int(stripped, 2)
            elif len(stripped) <= 8 and all(c in "01" for c in stripped):
                result = int(stripped, 2)
            else:
                raise ValueError(f"Cannot parse bits from {value!r}")

        elif isinstance(value, int):
            result = value

        else:
            raise ValueError(f"Cannot convert {type(value).__name__} to Bits")

        if not 0 <= result <= 255:
            raise ValueError(f"Bits value must be 0–255, got {result}")

        return super().__new__(cls, result)

    @property
    def positions(self) -> list[int]:
        """Sorted list of set bit positions (0-indexed)."""
        return [i for i in range(8) if self & (1 << i)]

    def __str__(self) -> str:
        return f"0b{self:08b}"

    def __repr__(self) -> str:
        return str(self)
