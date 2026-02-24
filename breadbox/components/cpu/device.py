from typing import Literal

from pydantic import PositiveFloat

from breadbox.types.device import Device


class CpuDevice(Device):
    component_type: str = "cpu"
    type: Literal["6502", "65c02"] = "6502"
    clock_mhz: PositiveFloat

    @property
    def clock_hz(self) -> int:
        return int(self.clock_mhz * 1_000_000)
