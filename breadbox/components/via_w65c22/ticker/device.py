from dataclasses import dataclass, field

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.types.device import Device


@dataclass(kw_only=True)
class ViaW65c22TickerDevice(Device):
    provider: str
    provider_device: ViaW65c22Device
    clock_hz: int
    ms_per_tick: int = 10
    cycles_per_tick: int = field(init=False)

    def __post_init__(self) -> None:
        super().__post_init__()
        if self.ms_per_tick < 1:
            raise ValueError(f"Device {self.id!r}: ms_per_tick must be >= 1")

        # Compute the timout value to use for T1, to honor the ms_per_tick.
        cycles_per_ms = self.clock_hz // 1000
        cycles_per_tick = self.ms_per_tick * cycles_per_ms - 2 # data sheet says: timer N -> N + 2 delay.
        if cycles_per_tick > 0xffff:
            raise ValueError(
                f"Device {self.id!r}: ms_per_tick too high "
                f"(requires {cycles_per_tick} cycles per tick, but max cycles is 65535)"
            )
        self.cycles_per_tick = cycles_per_tick
