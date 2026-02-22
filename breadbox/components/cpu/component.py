from typing import Any

from breadbox.components.cpu.device import CpuDevice
from breadbox.components.cpu.settings import CpuSettings
from breadbox.config import BreadboxConfig


def resolve(config: BreadboxConfig, device_settings: dict[str, Any]) -> CpuDevice:
    settings = CpuSettings.model_validate(device_settings, extra="forbid")
    return CpuDevice(settings=settings)
