from abc import ABC, abstractmethod

from pydantic import BaseModel


class Device(ABC, BaseModel):
    
    @abstractmethod
    def get_info(self) -> dict[str, str]:
        """Returns a human readable key/value pair list, describing the device."""
        raise NotImplementedError
