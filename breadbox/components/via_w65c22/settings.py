from pydantic import BaseModel

from breadbox.types.address16 import Address16


class ViaW65c22Settings(BaseModel):
    address: Address16
