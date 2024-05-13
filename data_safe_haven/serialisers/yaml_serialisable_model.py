"""A pydantic BaseModel that can be serialised to and from YAML"""

from difflib import unified_diff
from pathlib import Path
from typing import ClassVar, TypeVar

import yaml
from pydantic import BaseModel, ValidationError

from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.types import PathType

T = TypeVar("T", bound="YAMLSerialisableModel")


class YAMLSerialisableModel(BaseModel, validate_assignment=True):
    """
    A pydantic BaseModel that can be serialised to and from YAML
    """

    config_type: ClassVar[str] = "YAMLSerialisableModel"

    def yaml_diff(self, other: T) -> list[str]:
        return list(
            unified_diff(
                other.to_yaml().split(),
                self.to_yaml().split(),
                fromfile="remote",
                tofile="local",
            )
        )

    @classmethod
    def from_filepath(cls: type[T], config_file_path: PathType) -> T:
        """Construct a YAMLSerialisableModel from a YAML file"""
        try:
            with open(Path(config_file_path), encoding="utf-8") as f_yaml:
                settings_yaml = f_yaml.read()
            return cls.from_yaml(settings_yaml)
        except FileNotFoundError as exc:
            msg = f"Could not find file {config_file_path}.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

    @classmethod
    def from_yaml(cls: type[T], settings_yaml: str) -> T:
        """Construct a YAMLSerialisableModel from a YAML string"""
        try:
            settings_dict = yaml.safe_load(settings_yaml)
        except yaml.YAMLError as exc:
            msg = f"Could not parse {cls.config_type} configuration as YAML.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

        if not isinstance(settings_dict, dict):
            msg = f"Unable to parse {cls.config_type} configuration as a dict."
            raise DataSafeHavenConfigError(msg)

        try:
            return cls.model_validate(settings_dict)
        except ValidationError as exc:
            msg = f"Could not load {cls.config_type} configuration.\n{exc}"
            raise DataSafeHavenParameterError(msg) from exc

    def to_filepath(self, config_file_path: PathType) -> None:
        """Serialise a YAMLSerialisableModel to a YAML file"""
        # Create the parent directory if it does not exist then write YAML
        _config_file_path = Path(config_file_path)
        _config_file_path.parent.mkdir(parents=True, exist_ok=True)

        with open(_config_file_path, "w", encoding="utf-8") as f_yaml:
            f_yaml.write(self.to_yaml())

    def to_yaml(self) -> str:
        """Serialise a YAMLSerialisableModel to a YAML string"""
        return yaml.dump(self.model_dump(by_alias=True, mode="json"), indent=2)
