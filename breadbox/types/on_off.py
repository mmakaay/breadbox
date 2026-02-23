from typing import Annotated, Literal

from pydantic import GetCoreSchemaHandler
from pydantic_core import core_schema


def _parse_on_off(value: object) -> Literal["on", "off"]:
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in ("on", "true", "1", "yes"):
            return "on"
        if normalized in ("off", "false", "0", "no"):
            return "off"
        raise ValueError(f"Cannot convert string {value!r} to 'on'/'off'")
    if isinstance(value, bool):
        return "on" if value else "off"
    if isinstance(value, int):
        if value == 1:
            return "on"
        if value == 0:
            return "off"
        raise ValueError(f"Integer {value!r} is not 0 or 1")
    raise ValueError(f"Cannot convert {type(value).__name__!r} to 'on'/'off'")


class _OnOffPydanticAnnotation:
    @classmethod
    def __get_pydantic_core_schema__(
            cls, source_type: object, handler: GetCoreSchemaHandler
    ) -> core_schema.CoreSchema:
        return core_schema.no_info_plain_validator_function(
            _parse_on_off,
            serialization=core_schema.plain_serializer_function_ser_schema(str),
        )


OnOff = Annotated[Literal["on", "off"], _OnOffPydanticAnnotation]
