from typing import Any

from breadbox.components.cpu.device import CpuDevice
from breadbox.components.cpu.settings import CpuSettings
from breadbox.config import BreadboxConfig
from breadbox.types.device_identifier import DeviceIdentifier


def resolve(config: BreadboxConfig, device_id: DeviceIdentifier, device_settings: dict[str, Any]) -> CpuDevice:
    settings = CpuSettings.model_validate(device_settings, extra="forbid")
    return CpuDevice(id=device_id, settings=settings)
