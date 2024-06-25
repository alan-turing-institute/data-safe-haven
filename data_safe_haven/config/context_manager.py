"""Load global and local settings from dotfiles"""

# For postponed evaluation of annotations https://peps.python.org/pep-0563
from __future__ import (
    annotations,
)

from logging import Logger
from pathlib import Path
from typing import ClassVar

from pydantic import Field, model_validator

from data_safe_haven.context import Context
from data_safe_haven.directories import config_dir
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.functions import json_safe
from data_safe_haven.logging import get_logger
from data_safe_haven.serialisers import YAMLSerialisableModel


class ContextManager(YAMLSerialisableModel):
    """Load available and current contexts from YAML files structured as follows:

    selected: acmedeployment
    contexts:
        acmedeployment:
            name: Acme Deployment
            subscription_name: Data Safe Haven (Acme)
        acmetesting:
            name: Acme Testing
            subscription_name: Data Safe Haven (Acme Testing)
        ...
    """

    config_type: ClassVar[str] = "ContextManager"
    selected_: str | None = Field(..., alias="selected")
    contexts: dict[str, Context]
    logger: ClassVar[Logger] = get_logger()

    @model_validator(mode="after")
    def ensure_selected_is_valid(self) -> ContextManager:
        if self.selected is not None:
            if self.selected not in self.available:
                msg = f"Selected context '{self.selected}' is not defined."
                raise ValueError(msg)
        return self

    @staticmethod
    def default_config_file_path() -> Path:
        return config_dir() / "contexts.yaml"

    @property
    def selected(self) -> str | None:
        return self.selected_

    @selected.setter
    def selected(self, context_name: str | None) -> None:
        if context_name in self.available or context_name is None:
            self.selected_ = context_name
            self.logger.info(f"Switched context to '{context_name}'.")
        else:
            msg = f"Context '{context_name}' is not defined."
            raise DataSafeHavenParameterError(msg)

    @property
    def context(self) -> Context | None:
        if self.selected is None:
            return None
        else:
            return self.contexts[self.selected]

    def assert_context(self) -> Context:
        if context := self.context:
            return context
        else:
            msg = "No context selected"
            raise DataSafeHavenConfigError(msg)

    @property
    def available(self) -> list[str]:
        return list(self.contexts.keys())

    def update(
        self,
        *,
        name: str | None = None,
        subscription_name: str | None = None,
    ) -> None:
        context = self.assert_context()

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
        name: str,
        subscription_name: str,
    ) -> None:
        # Ensure context is not already present
        key = json_safe(name)
        if key in self.available:
            msg = f"A context with key '{key}' is already defined."
            raise DataSafeHavenParameterError(msg)

        self.logger.info(f"Creating a new context with key '{key}'.")
        self.contexts[key] = Context(
            name=name,
            subscription_name=subscription_name,
        )
        if not self.selected:
            self.selected = key

    def remove(self, key: str) -> None:
        if key not in self.available:
            msg = f"No context with key '{key}'."
            raise DataSafeHavenParameterError(msg)

        del self.contexts[key]

        # Prevent having a deleted context selected
        if key == self.selected:
            self.selected = None

    @classmethod
    def from_file(cls, config_file_path: Path | None = None) -> ContextManager:
        if config_file_path is None:
            config_file_path = cls.default_config_file_path()
        cls.logger.debug(
            f"Reading project settings from '[green]{config_file_path}[/]'."
        )
        return cls.from_filepath(config_file_path)

    def write(self, config_file_path: Path | None = None) -> None:
        """Write settings to YAML file"""
        if config_file_path is None:
            config_file_path = self.default_config_file_path()
        self.to_filepath(config_file_path)
        self.logger.debug(f"Saved context settings to '[green]{config_file_path}[/]'.")
