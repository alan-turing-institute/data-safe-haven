"""Load global and local settings from dotfiles"""

# For postponed evaluation of annotations https://peps.python.org/pep-0563
from __future__ import annotations

from logging import Logger
from pathlib import Path
from typing import ClassVar

from pydantic import Field, model_validator

from data_safe_haven.directories import config_dir
from data_safe_haven.exceptions import DataSafeHavenConfigError, DataSafeHavenValueError
from data_safe_haven.logging import get_logger
from data_safe_haven.serialisers import YAMLSerialisableModel

from .context import Context


class ContextManager(YAMLSerialisableModel):
    """Load available and current contexts from YAML files structured as follows:

    selected: acmedeployment
    contexts:
        acmedeployment:
            admin_group_name: Acme Admins
            description: Acme Deployment
            name: acmedeployment
            subscription_name: Data Safe Haven (Acme)
        acmetesting:
            admin_group_name: Acme Testing Admins
            description: Acme Testing
            name: acmetesting
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
    def selected(self, name: str | None) -> None:
        if name in self.available or name is None:
            self.selected_ = name
            self.logger.info(f"Switched context to '{name}'.")
        else:
            msg = f"Context '{name}' is not defined."
            raise DataSafeHavenValueError(msg)

    @property
    def context(self) -> Context | None:
        if self.selected is None:
            return None
        else:
            return self.contexts[self.selected]

    @property
    def available(self) -> list[str]:
        return list(self.contexts.keys())

    def assert_context(self) -> Context:
        if context := self.context:
            return context
        else:
            msg = "No context selected."
            raise DataSafeHavenConfigError(msg)

    def update(
        self,
        *,
        admin_group_name: str | None = None,
        description: str | None = None,
        name: str | None = None,
        subscription_name: str | None = None,
    ) -> None:
        context = self.assert_context()

        if admin_group_name:
            self.logger.debug(
                f"Updating admin group name from '{context.admin_group_name}' to '[green]{admin_group_name}[/]'."
            )
            context.admin_group_name = admin_group_name
        if description:
            self.logger.debug(
                f"Updating description from '{context.description}' to '[green]{description}[/]'."
            )
            context.description = description
        if name:
            self.logger.debug(
                f"Updating name from '{context.name}' to '[green]{name}[/]'."
            )
            context.name = name
        if subscription_name:
            self.logger.debug(
                f"Updating subscription name from '{context.subscription_name}' to '[green]{subscription_name}[/]'."
            )
            context.subscription_name = subscription_name

        # If the name has changed we also need to change the key
        if name:
            self.contexts[name] = context
            if self.selected:
                del self.contexts[self.selected]
            self.selected = name

    def add(
        self,
        *,
        admin_group_name: str,
        description: str,
        name: str,
        subscription_name: str,
    ) -> None:
        # Ensure context is not already present
        if name in self.available:
            msg = f"A context with name '{name}' is already defined."
            raise DataSafeHavenValueError(msg)

        self.logger.info(f"Creating a new context with name '{name}'.")
        self.contexts[name] = Context(
            admin_group_name=admin_group_name,
            description=description,
            name=name,
            subscription_name=subscription_name,
        )
        if not self.selected:
            self.selected = name

    def remove(self, name: str) -> None:
        if name not in self.available:
            msg = f"No context with name '{name}'."
            raise DataSafeHavenValueError(msg)
        del self.contexts[name]

        # Prevent having a deleted context selected
        if name == self.selected:
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
