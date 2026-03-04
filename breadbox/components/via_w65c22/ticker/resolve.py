from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.ticker.device import ViaW65c22TickerDevice
from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    provider_device: ViaW65c22Device,
    device_settings: dict[str, Any],
) -> Component:
    device = ViaW65c22TickerDevice(
        id=component_id,
        provider_device=provider_device,
        clock_hz = breadbox.core.clock_hz,
        **device_settings,
    )

    return device
