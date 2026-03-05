from dataclasses import dataclass, field

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.types.device import Device


@dataclass(kw_only=True)
class TimerSlot:
    """A fixed-period software timer managed by the ticker ISR."""

    name: str
    ms: int
    ticks: int

    @property
    def byte_width(self) -> int:
        if self.ticks <= 0xFF:
            return 1
        if self.ticks <= 0xFFFF:
            return 2
        raise ValueError(f"Timer '{self.name}' period {self.ticks} ticks exceeds 16-bit range")


@dataclass(kw_only=True)
class ViaW65c22TickerDevice(Device):
    provider: str
    provider_device: ViaW65c22Device
    clock_hz: int
    ms_per_tick: int = 10
    cycles_per_tick: int = field(init=False)
    timers: list[TimerSlot] = field(default_factory=list)

    def __post_init__(self) -> None:
        super().__post_init__()
        if self.ms_per_tick < 1:
            raise ValueError(f"Device {self.id!r}: ms_per_tick must be >= 1")

        # Compute the timeout value to use for T1, to honor the ms_per_tick.
        cycles_per_ms = self.clock_hz // 1000
        cycles_per_tick = self.ms_per_tick * cycles_per_ms - 2  # data sheet says: timer N -> N + 2 delay.
        if cycles_per_tick > 0xFFFF:
            raise ValueError(
                f"Device {self.id!r}: ms_per_tick too high "
                f"(requires {cycles_per_tick} cycles per tick, but max cycles is 65535)"
            )
        self.cycles_per_tick = cycles_per_tick
