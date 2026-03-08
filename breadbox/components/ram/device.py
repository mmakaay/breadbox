from __future__ import annotations

from dataclasses import dataclass, field

from breadbox.types.address16 import Address16
from breadbox.types.device import Device
from breadbox.types.memory_size import MemorySize


@dataclass(kw_only=True)
class RamDevice(Device):
    """
    RAM memory region.

    Defines a contiguous RAM address range for the linker configuration.
    ZEROPAGE ($0000-$00FF) and STACK ($0100-$01FF) are automatically carved
    from the RAM device that covers those addresses.
    """

    address: Address16
    size: MemorySize
    segments: list[str] = field(default_factory=list)

    _internal_fields = Device._internal_fields | {"segments"}

    def __post_init__(self) -> None:
        super().__post_init__()
        if self.size <= 0:
            raise ValueError(f"RAM size must be positive, got {self.size}")
        if int(self.address) + self.size > 0x10000:
            raise ValueError(f"RAM region {self.address}+${self.size:04X} exceeds 16-bit address space")

    @property
    def end_address(self) -> int:
        """Exclusive end address (first byte after this region)."""
        return int(self.address) + self.size

    def covers(self, start: int, end: int) -> bool:
        """Check if this RAM fully covers the address range [start, end)."""
        return int(self.address) <= start and self.end_address >= end
