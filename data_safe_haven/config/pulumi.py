from __future__ import annotations

from typing import Any, ClassVar

from pydantic import BaseModel

from data_safe_haven.config import ConfigClass


class DSHPulumiProject(BaseModel, validate_assignment=True):
    """Container for DSH Pulumi Project persistent information"""

    stack_config: dict[str, Any]

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, DSHPulumiProject):
            return NotImplemented
        return self.stack_config == other.stack_config

    def __hash__(self) -> int:
        return hash(self.stack_config)


class DSHPulumiConfig(ConfigClass):
    config_type: ClassVar[str] = "Pulumi"
    filename: ClassVar[str] = "pulumi.yaml"
    projects: dict[str, DSHPulumiProject]

    def __getitem__(self, key: str) -> DSHPulumiProject:
        if not isinstance(key, str):
            msg = "'key' must be a string."
            raise TypeError(msg)

        if key not in self.projects.keys():
            msg = f"No configuration for DSH Pulumi Project {key}."
            raise KeyError(msg)

        return self.projects[key]

    def __setitem__(self, key: str, value: DSHPulumiProject) -> None:
        """
        Add a DSH Pulumi Project.
        This method does not support modifying existing projects.
        """
        if not isinstance(key, str):
            msg = "'key' must be a string."
            raise TypeError(msg)

        if key in self.project_names:
            msg = f"Stack {key} already exists."
            raise ValueError(msg)

        self.projects[key] = value

    def __delitem__(self, key: str) -> None:
        if not isinstance(key, str):
            msg = "'key' must be a string."
            raise TypeError(msg)

        if key not in self.projects.keys():
            msg = f"No configuration for DSH Pulumi Project {key}."
            raise KeyError(msg)

        del self.projects[key]

    @property
    def project_names(self) -> list[str]:
        """Produce a list of known DSH Pulumi Project names"""
        return list(self.projects.keys())

    def create_or_select_project(self, project_name: str) -> DSHPulumiProject:
        if project_name not in self.project_names:
            self[project_name] = DSHPulumiProject(stack_config={})
        return self[project_name]
