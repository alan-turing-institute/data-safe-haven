"""A pydantic BaseModel that can be serialised to and from YAML"""

from difflib import unified_diff
from pathlib import Path
from typing import ClassVar, TypeVar

import yaml
from pydantic import BaseModel, ValidationError

from data_safe_haven.exceptions import DataSafeHavenConfigError, DataSafeHavenTypeError
from data_safe_haven.logging import get_logger
from data_safe_haven.types import PathType

T = TypeVar("T", bound="YAMLSerialisableModel")


class YAMLSerialisableModel(BaseModel, validate_assignment=True):
    """
    A pydantic BaseModel that can be serialised to and from YAML
    """

    config_type: ClassVar[str] = "YAMLSerialisableModel"

    @classmethod
    def from_filepath(cls: type[T], config_file_path: PathType) -> T:
        """Construct a YAMLSerialisableModel from a YAML file"""
        try:
            with open(Path(config_file_path), encoding="utf-8") as f_yaml:
                settings_yaml = f_yaml.read()
            return cls.from_yaml(settings_yaml)
        except FileNotFoundError as exc:
            msg = f"Could not find file {config_file_path}."
            raise DataSafeHavenConfigError(msg) from exc

    @classmethod
    def from_yaml(cls: type[T], settings_yaml: str) -> T:
        """Construct a YAMLSerialisableModel from a YAML string"""
        try:
            settings_dict = yaml.safe_load(settings_yaml)
        except yaml.YAMLError as exc:
            msg = f"Could not parse {cls.config_type} configuration as YAML."
            raise DataSafeHavenConfigError(msg) from exc

        if not isinstance(settings_dict, dict):
            msg = f"Unable to parse {cls.config_type} configuration as a dict."
            raise DataSafeHavenConfigError(msg)

        try:
            return cls.model_validate(settings_dict)
        except ValidationError as exc:
            logger = get_logger()
            logger.error(
                f"Found {exc.error_count()} validation errors when trying to load {cls.config_type}."
            )
            for error in exc.errors():
                logger.error(
                    f"[red]{'.'.join(map(str, error.get('loc', [])))}: {error.get('input', '')}[/] - {error.get('msg', '')}"
                )
            msg = f"{cls.config_type} configuration is invalid."
            raise DataSafeHavenTypeError(msg) from exc

    def to_filepath(self, config_file_path: PathType) -> None:
        """Serialise a YAMLSerialisableModel to a YAML file"""
        # Create the parent directory if it does not exist then write YAML
        _config_file_path = Path(config_file_path)
        _config_file_path.parent.mkdir(parents=True, exist_ok=True)

        with open(_config_file_path, "w", encoding="utf-8") as f_yaml:
            f_yaml.write(self.to_yaml())

    def to_yaml(self, *, warnings: bool = True) -> str:
        """Serialise a YAMLSerialisableModel to a YAML string"""
        return yaml.dump(
            self.model_dump(by_alias=True, mode="json", warnings=warnings), indent=2
        )

    def yaml_diff(
        self, other: T, from_name: str = "other", to_name: str = "self"
    ) -> list[str]:
        """
        Determine the diff of YAML output from `other` to `self`.

        The diff is given in unified diff format.
        """
        return list(
            unified_diff(
                other.to_yaml().splitlines(keepends=True),
                self.to_yaml().splitlines(keepends=True),
                fromfile=from_name,
                tofile=to_name,
            )
        )
