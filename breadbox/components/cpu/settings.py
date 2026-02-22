from typing import Literal

from pydantic import BaseModel, PositiveFloat


class CpuSettings(BaseModel):
    type: Literal["6502", "65c02"] = "6502"
    clock_mhz: PositiveFloat

    @property
    def clock_hz(self) -> int:
        return int(self.clock_mhz * 1_000_000)
