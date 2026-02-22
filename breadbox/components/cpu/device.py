from breadbox.components.cpu.settings import CpuSettings
from breadbox.types.device import Device


class CpuDevice(Device):
    settings: CpuSettings

    def get_info(self) -> dict[str, str]:
        def format_mhz(hz: int) -> str:
            if hz < 1_000:
                return f"{hz} Hz"
            if hz < 1_000_000:
                return f"{hz / 1_000:.3g} kHz"
            return f"{hz / 1_000_000:.3g} MHz"

        return {
            "type": self.settings.type,
            "speed": format_mhz(self.settings.clock_hz)
        }
