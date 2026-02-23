from typing import Any

from pydantic import GetCoreSchemaHandler
from pydantic_core import core_schema


class PinDirection(str):
    """Pin data direction: in, out, or both."""

    @classmethod
    def __get_pydantic_core_schema__(cls, source_type: Any, handler: GetCoreSchemaHandler):
        return core_schema.no_info_plain_validator_function(
            cls._validate,
            serialization=core_schema.to_string_ser_schema(),
        )

    @classmethod
    def _validate(cls, value: Any) -> "PinDirection":
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized not in ("in", "out", "both"):
                raise ValueError(
                    f"Cannot parse direction from {type(value).__name__!r} "
                    "(must be 'in', 'out' or 'both'"
                )
            return cls(normalized)
        raise ValueError(f"Cannot parse direction from {type(value).__name__!r}")

    def __repr__(self) -> str:
        return f"PinDirection({self})"
