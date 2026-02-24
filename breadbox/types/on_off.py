from typing import Self


class OnOff(str):
    """On/off value, accepting various truthy/falsy inputs."""

    def __new__(cls, value: object) -> Self:
        if isinstance(value, cls):
            return value
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in ("on", "true", "1", "yes"):
                return super().__new__(cls, "on")
            if normalized in ("off", "false", "0", "no"):
                return super().__new__(cls, "off")
            raise ValueError(f"Cannot convert string {value!r} to 'on'/'off'")
        if isinstance(value, bool):
            return super().__new__(cls, "on" if value else "off")
        if isinstance(value, int):
            if value == 1:
                return super().__new__(cls, "on")
            if value == 0:
                return super().__new__(cls, "off")
            raise ValueError(f"Integer {value!r} is not 0 or 1")
        raise ValueError(f"Cannot convert {type(value).__name__!r} to 'on'/'off'")

    def __repr__(self) -> str:
        return str(self)
