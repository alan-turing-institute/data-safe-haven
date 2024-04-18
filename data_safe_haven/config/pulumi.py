from __future__ import annotations

from typing import Annotated

import yaml
from pydantic import BaseModel, PlainSerializer
from pydantic.functional_validators import AfterValidator

from data_safe_haven.functions import b64decode, b64encode
from data_safe_haven.utility.annotated_types import UniqueList


def base64_string_decode(v: str) -> str:
    """Pydantic validator function for decoding base64"""
    return b64decode(v)


B64String = Annotated[
    str,
    PlainSerializer(b64encode, return_type=str),
    AfterValidator(base64_string_decode),
]


class PulumiStack(BaseModel, validate_assignment=True):
    """Container for Pulumi Stack persistent information"""

    name: str
    config: B64String

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, PulumiStack):
            return NotImplemented
        return self.name == other.name or self.config == other.config

    def __hash__(self) -> int:
        return hash(self.name)


class PulumiConfig(BaseModel, validate_assignment=True):
    stacks: UniqueList[PulumiStack]

    def __getitem__(self, key: str) -> PulumiStack:
        if not isinstance(key, str):
            msg = "'key' must be a string."
            raise TypeError(msg)

        for stack in self.stacks:
            if stack.name == key:
                return stack

        msg = f"No configuration for Pulumi stack {key}."
        raise IndexError(msg)

    def __setitem__(self, key: str, value: PulumiStack) -> None:
        """
        Add a pulumi stack.
        This method does not support modifying existing stacks.
        """
        if not isinstance(key, str):
            msg = "'key' must be a string."
            raise TypeError(msg)

        if key in self.stack_names:
            msg = f"Stack {key} already exists."
            raise ValueError(msg)

        self.stacks.append(value)

    def __delitem__(self, key: str) -> None:
        if not isinstance(key, str):
            msg = "'key' must be a string."
            raise TypeError(msg)

        for stack in self.stacks:
            if stack.name == key:
                self.stacks.remove(stack)
                return

        msg = f"No configuration for Pulumi stack {key}."
        raise IndexError(msg)

    @property
    def stack_names(self) -> list[str]:
        """Produce a list of known Pulumi stack names"""
        return [stack.name for stack in self.stacks]

    def to_yaml(self) -> str:
        """Write Pulumi configuration to a YAML formatted string"""
        return yaml.dump(self.model_dump(mode="json"), indent=2)