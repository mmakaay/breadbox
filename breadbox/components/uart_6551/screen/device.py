from dataclasses import dataclass

from breadbox.components.uart_6551.device import Uart6551Device
from breadbox.types.device import Device


@dataclass(kw_only=True)
class Uart6551Screen(Device):
    provider_device: Uart6551Device
    provider: str
    width: int = 80
    """
    Terminal width in columns. Used by the TTY layer for wrap-aware
    cursor positioning. Defaults to 80, the de facto standard. Can be
    overridden in config.yaml for terminals known to have a different
    width, or refreshed at runtime via SCREEN::query_size which uses
    DSR (ESC[6n) to ask the terminal directly.
    """
    height: int = 24
    """
    Terminal height in rows. Used by the TTY layer to detect when a
    long line will scroll off the screen. Defaults to 24.
    """

    def __post_init__(self) -> None:
        super().__post_init__()
        self._internal_fields.add("provider_device")
