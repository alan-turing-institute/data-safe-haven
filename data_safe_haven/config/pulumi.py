from typing import Annotated

from pydantic import BaseModel, PlainSerializer
from pydantic.functional_validators import AfterValidator

from data_safe_haven.functions import b64encode, b64decode


def base64_string_decode(v: str) -> str:
    return b64decode(v)


B64String = Annotated[
    str,
    PlainSerializer(b64encode, return_type=str),
    AfterValidator(base64_string_decode)
]


class PulumiStack(BaseModel, validate_assignment=True):
    name: str
    config: B64String


class PulumiConfig(BaseModel, validate_assignment=True):
    stacks: list[PulumiStack]
