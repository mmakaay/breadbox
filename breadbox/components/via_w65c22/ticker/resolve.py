from typing import Any

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.ticker.device import TimerSlot, ViaW65c22TickerDevice
from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    provider_device: ViaW65c22Device,
    device_settings: dict[str, Any],
) -> Component:
    timers_raw = device_settings.pop("timers", {})
    ms_per_tick = device_settings.get("ms_per_tick", 10)

    timers = []
    for name, ms in timers_raw.items():
        ticks = ms // ms_per_tick
        if ticks < 1:
            raise ValueError(
                f"Timer '{name}' in {component_id!r}: period {ms}ms is less than one tick ({ms_per_tick}ms/tick)"
            )
        timers.append(TimerSlot(name=name, ms=ms, ticks=ticks))

    device = ViaW65c22TickerDevice(
        id=component_id,
        provider_device=provider_device,
        clock_hz=breadbox.core.clock_hz,
        timers=timers,
        **device_settings,
    )

    return device
