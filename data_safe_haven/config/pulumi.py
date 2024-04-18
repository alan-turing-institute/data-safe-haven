from typing import Annotated

from pydantic import BaseModel, PlainSerializer
from pydantic.functional_validators import AfterValidator
import yaml

from data_safe_haven.functions import b64decode, b64encode
from data_safe_haven.utility.annotated_types import UniqueList


def base64_string_decode(v: str) -> str:
    return b64decode(v)


B64String = Annotated[
    str,
    PlainSerializer(b64encode, return_type=str),
    AfterValidator(base64_string_decode),
]


class PulumiStack(BaseModel, validate_assignment=True):
    name: str
    config: B64String

    def __eq__(self, other):
        return self.name == other.name or self.config == other.config

    def __hash__(self):
        return hash(self.name)


class PulumiConfig(BaseModel, validate_assignment=True):
    stacks: UniqueList[PulumiStack]

    def __getitem__(self, key: str):
        if not isinstance(key, str):
            msg = "'key' must be a string."
            raise TypeError(msg)

        for stack in self.stacks:
            if stack.name == key:
                return stack

        msg = f"No configuration for Pulumi stack {key}."
        raise IndexError(msg)

    @property
    def stack_names(self):
        return [stack.name for stack in self.stacks]

    def to_yaml(self) -> str:
        return yaml.dump(self.model_dump(mode="json"), indent=2)
