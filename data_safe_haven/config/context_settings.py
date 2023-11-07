"""Load global and local settings from dotfiles"""
# For postponed evaluation of annotations https://peps.python.org/pep-0563
from __future__ import (
    annotations,
)

from pathlib import Path
from typing import Any, ClassVar

import yaml
from pydantic import BaseModel, Field, ValidationError
from yaml.parser import ParserError

from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.utility import LoggingSingleton, config_dir


def default_config_file_path() -> Path:
    return config_dir() / "contexts.yaml"


class Context(BaseModel):
    admin_group_id: str
    location: str
    name: str
    subscription_name: str


class ContextSettings(BaseModel):
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

    selected_: str = Field(..., alias="selected")
    contexts: dict[str, Context]
    logger: ClassVar[LoggingSingleton] = LoggingSingleton()

    @property
    def selected(self) -> str:
        return str(self.selected_)

    @selected.setter
    def selected(self, context_name: str) -> None:
        if context_name in self.available:
            self.selected_ = context_name
            self.logger.info(f"Switched context to '{context_name}'.")
        else:
            msg = f"Context '{context_name}' is not defined."
            raise DataSafeHavenParameterError(msg)

    @property
    def context(self) -> Context:
        return self.contexts[self.selected]

    @property
    def available(self) -> list[str]:
        return list(self.contexts.keys())

    def update(
        self,
        *,
        admin_group_id: str | None = None,
        location: str | None = None,
        name: str | None = None,
        subscription_name: str | None = None,
    ) -> None:
        context = self.contexts[self.selected]

        if admin_group_id:
            self.logger.debug(
                f"Updating '[green]{admin_group_id}[/]' to '{admin_group_id}'."
            )
            context.admin_group_id = admin_group_id
        if location:
            self.logger.debug(f"Updating '[green]{location}[/]' to '{location}'.")
            context.location = location
        if name:
            self.logger.debug(f"Updating '[green]{name}[/]' to '{name}'.")
            context.name = name
        if subscription_name:
            self.logger.debug(
                f"Updating '[green]{subscription_name}[/]' to '{subscription_name}'."
            )
            context.subscription_name = subscription_name

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
        if key in self.available:
            msg = f"A context with key '{key}' is already defined."
            raise DataSafeHavenParameterError(msg)

        self.contexts[key] = Context(
            name=name,
            admin_group_id=admin_group_id,
            location=location,
            subscription_name=subscription_name,
        )

    def remove(self, key: str) -> None:
        if key not in self.available:
            msg = f"No context with key '{key}'."
            raise DataSafeHavenParameterError(msg)
        del self.contexts[key]

    @classmethod
    def from_yaml(cls, settings_yaml: str) -> ContextSettings:
        try:
            settings_dict = yaml.safe_load(settings_yaml)
        except ParserError as exc:
            msg = f"Could not parse context settings as YAML.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

        if not isinstance(settings_dict, dict):
            msg = "Unable to parse context settings as a dict."
            raise DataSafeHavenConfigError(msg)

        try:
            return ContextSettings.model_validate(settings_dict)
        except ValidationError as exc:
            cls.logger.error(f"{exc.error_count()} errors found in context settings:")
            for error in exc.errors():
                cls.logger.error(f"{error['msg']} at '{'->'.join(error['loc'])}'")
            msg = f"Could not load context settings.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

    @classmethod
    def from_file(cls, config_file_path: Path | None = None) -> ContextSettings:
        if config_file_path is None:
            config_file_path = default_config_file_path()
        cls.logger.info(
            f"Reading project settings from '[green]{config_file_path}[/]'."
        )
        try:
            with open(config_file_path, encoding="utf-8") as f_yaml:
                settings_yaml = f_yaml.read()
            return cls.from_yaml(settings_yaml)
        except FileNotFoundError as exc:
            msg = f"Could not find file {config_file_path}.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

    def write(self, config_file_path: Path | None = None) -> None:
        """Write settings to YAML file"""
        if config_file_path is None:
            config_file_path = default_config_file_path()
        # Create the parent directory if it does not exist then write YAML
        config_file_path.parent.mkdir(parents=True, exist_ok=True)

        with open(config_file_path, "w", encoding="utf-8") as f_yaml:
            yaml.dump(self.model_dump(), f_yaml, indent=2)
        self.logger.info(f"Saved context settings to '[green]{config_file_path}[/]'.")
