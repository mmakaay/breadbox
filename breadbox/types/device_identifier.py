import re
from typing import Any

from pydantic_core import core_schema

_DEVICE_ID_RE = re.compile(r'^[A-Za-z][A-Za-z0-9_]{3,}$')


class DeviceIdentifier(str):
    """Device identifier: starts with a letter, min 4 chars, letters/digits/underscores only."""

    @classmethod
    def __get_pydantic_core_schema__(cls, source_type: Any, handler):
        return core_schema.no_info_plain_validator_function(cls._validate)

    @classmethod
    def _validate(cls, value: Any) -> "DeviceIdentifier":
        if not isinstance(value, str):
            raise ValueError(f"Expected a string, got {type(value).__name__!r}")

        # Special value that is allowed, even though it is only 3 chars long.
        if value.lower() == "cpu":
            return cls(value)

        if not _DEVICE_ID_RE.match(value):
            raise ValueError(
                f"{value!r} is not a valid DeviceIdentifier "
                f"(must start with a letter, min 4 chars, letters/digits/underscores only)"
            )
        return cls(value)

    def __repr__(self) -> str:
        return f"DeviceIdentifier({str(self)!r})"
