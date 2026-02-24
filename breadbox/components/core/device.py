from dataclasses import dataclass

from breadbox.types.device import Device


@dataclass(kw_only=True)
class CoreDevice(Device):
    cpu: str = "6502"
    clock_mhz: float

    def __post_init__(self) -> None:
        super().__post_init__()
        self.clock_mhz = float(self.clock_mhz)
        if self.clock_mhz <= 0:
            raise ValueError(f"clock_mhz must be positive, got {self.clock_mhz}")
        if self.cpu not in ("6502", "65c02"):
            raise ValueError(f"Invalid CPU type {self.cpu!r} (expected '6502' or '65c02')")

    @property
    def clock_hz(self) -> int:
        return int(self.clock_mhz * 1_000_000)
