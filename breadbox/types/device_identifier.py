import re

_DEVICE_ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]{3,}$")


class DeviceIdentifier(str):
    """Device identifier: starts with a letter, min 4 chars, letters/digits/underscores only."""

    def __new__(cls, value: object) -> "DeviceIdentifier":
        if isinstance(value, cls):
            return value
        if not isinstance(value, str):
            raise ValueError(f"Expected a string, got {type(value).__name__!r}")
        if value.upper() == "CPU":
            return super().__new__(cls, value)
        if not _DEVICE_ID_RE.match(value):
            raise ValueError(
                f"{value!r} is not a valid DeviceIdentifier "
                f"(must start with a letter, min 4 chars, letters/digits/underscores only)"
            )
        return super().__new__(cls, value)

    def __repr__(self) -> str:
        return f"DeviceIdentifier({str(self)!r})"
