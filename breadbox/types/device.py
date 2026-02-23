from abc import ABC, abstractmethod

from pydantic import BaseModel


class Device[TSettings: BaseModel](ABC, BaseModel):
    component_type: str
    settings: TSettings

    def get_info(self) -> dict[str, str]:
        return {k: str(v) for k, v in self.settings.model_dump().items()}
