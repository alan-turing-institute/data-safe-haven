"""Load global and local settings from dotfiles"""
# For postponed evaluation of annotations https://peps.python.org/pep-0563
from __future__ import (
    annotations,
)

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml
from schema import Schema, SchemaError
from yaml.parser import ParserError

from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.utility import LoggingSingleton, config_dir


def default_config_file_path() -> Path:
    return config_dir() / "contexts.yaml"


@dataclass
class Context:
    admin_group_id: str
    location: str
    name: str
    subscription_name: str


class ContextSettings:
    """Load global and local settings from dotfiles with structure like the following

    selected: acme_deployment
    contexts:
        acme_deployment:
            name: Acme Deployment
            admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
            location: uksouth
            subscription_name: Data Safe Haven (Acme)
        ...
    """

    def __init__(self, settings_dict: dict[Any, Any]) -> None:
        self.logger = LoggingSingleton()

        context_schema = Schema(
            {
                "name": str,
                "admin_group_id": str,
                "location": str,
                "subscription_name": str,
            }
        )

        schema = Schema(
            {
                "selected": str,
                "contexts": Schema(
                    {
                        str: context_schema,
                    }
                ),
            }
        )

        try:
            self._settings: dict[Any, Any] = schema.validate(settings_dict)
        except SchemaError as exc:
            msg = f"Invalid context configuration file.\n{exc}"
            raise DataSafeHavenParameterError(msg) from exc

    @property
    def settings(self) -> dict[Any, Any]:
        return self._settings

    @property
    def selected(self) -> str:
        return str(self.settings["selected"])

    @selected.setter
    def selected(self, context_name: str) -> None:
        if context_name in self.settings["contexts"].keys():
            self.settings["selected"] = context_name
            self.logger.info(f"Switched context to '{context_name}'.")
        else:
            msg = f"Context '{context_name}' is not defined."
            raise DataSafeHavenParameterError(msg)

    @property
    def context(self) -> Context:
        return Context(**self.settings["contexts"][self.selected])

    @property
    def available(self) -> list[str]:
        return list(self.settings["contexts"].keys())

    def update(
        self,
        *,
        admin_group_id: str | None = None,
        location: str | None = None,
        name: str | None = None,
        subscription_name: str | None = None,
    ) -> None:
        context_dict = self.settings["contexts"][self.selected]

        if admin_group_id:
            self.logger.debug(
                f"Updating '[green]{admin_group_id}[/]' to '{admin_group_id}'."
            )
            context_dict["admin_group_id"] = admin_group_id
        if location:
            self.logger.debug(f"Updating '[green]{location}[/]' to '{location}'.")
            context_dict["location"] = location
        if name:
            self.logger.debug(f"Updating '[green]{name}[/]' to '{name}'.")
            context_dict["name"] = name
        if subscription_name:
            self.logger.debug(
                f"Updating '[green]{subscription_name}[/]' to '{subscription_name}'."
            )
            context_dict["subscription_name"] = subscription_name

    def add(
        self,
        *,
        key: str,
        name: str,
        admin_group_id: str,
        location: str,
        subscription_name: str,
    ) -> None:
        # Ensure context is not already present
        if key in self.settings["contexts"].keys():
            msg = f"A context with key '{key}' is already defined."
            raise DataSafeHavenParameterError(msg)

        self.settings["contexts"][key] = {
            "name": name,
            "admin_group_id": admin_group_id,
            "location": location,
            "subscription_name": subscription_name,
        }

    def remove(self, key: str) -> None:
        if key not in self.settings["contexts"].keys():
            msg = f"No context with key '{key}'."
            raise DataSafeHavenParameterError(msg)
        del self.settings["contexts"][key]

    @classmethod
    def from_file(cls, config_file_path: Path | None = None) -> ContextSettings:
        if config_file_path is None:
            config_file_path = default_config_file_path()
        logger = LoggingSingleton()
        try:
            with open(config_file_path, encoding="utf-8") as f_yaml:
                settings = yaml.safe_load(f_yaml)
            if isinstance(settings, dict):
                logger.info(
                    f"Reading project settings from '[green]{config_file_path}[/]'."
                )
                return cls(settings)
            else:
                msg = f"Unable to parse {config_file_path} as a dict."
                raise DataSafeHavenConfigError(msg)
        except FileNotFoundError as exc:
            msg = f"Could not find file {config_file_path}.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc
        except ParserError as exc:
            msg = f"Could not load settings from {config_file_path}.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

    def write(self, config_file_path: Path | None = None) -> None:
        """Write settings to YAML file"""
        if config_file_path is None:
            config_file_path = default_config_file_path()
        # Create the parent directory if it does not exist then write YAML
        config_file_path.parent.mkdir(parents=True, exist_ok=True)

        with open(config_file_path, "w", encoding="utf-8") as f_yaml:
            yaml.dump(self.settings, f_yaml, indent=2)
        self.logger.info(f"Saved context settings to '[green]{config_file_path}[/]'.")
