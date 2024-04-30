from __future__ import annotations

from typing import Any

from pydantic import BaseModel


class DSHPulumiProject(BaseModel, validate_assignment=True):
    """Container for DSH Pulumi Project persistent information"""

    stack_config: dict[str, Any]

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, DSHPulumiProject):
            return NotImplemented
        return self.stack_config == other.stack_config

    def __hash__(self) -> int:
        return hash(self.stack_config)
