from typing import Any

from breadbox.components.lcd_hd44780.screen.device import LcdHc44780Terminal
from breadbox.components.lcd_hd44780.device import LcdHd44780Device
from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    provider_device: LcdHd44780Device,
    device_settings: dict[str, Any],
) -> Component:
    return LcdHc44780Terminal(
        id=component_id,
        provider_device=provider_device,
        **device_settings,
    )
