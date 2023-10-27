"""Load global and local settings from dotfiles"""
import pathlib
from dataclasses import dataclass
from typing import Any

import appdirs
import yaml
from yaml.parser import ParserError

from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.utility import LoggingSingleton


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

    def __init__(self) -> None:
        self.logger = LoggingSingleton()

        self._settings: dict[Any, Any] | None = None

        config_directory = pathlib.Path(
            appdirs.user_config_dir(appname="data_safe_haven")
        ).resolve()
        self.config_file_path = config_directory / "config.yaml"

    @property
    def settings(self) -> dict[Any, Any]:
        if not self._settings:
            try:
                with open(self.config_file_path, encoding="utf-8") as f_yaml:
                    settings = yaml.safe_load(f_yaml)
                if isinstance(settings, dict):
                    self.logger.info(
                        f"Reading project settings from '[green]{self.config_file_path}[/]'."
                    )
                    self._settings = settings
                    self._context = Context(**settings.get("contexts").get(self._selected))
            except FileNotFoundError as exc:
                msg = f"Could not find file {self.config_file_path}.\n{exc}"
                raise DataSafeHavenConfigError(msg) from exc
            except ParserError as exc:
                msg = f"Could not load settings from {self.config_file_path}.\n{exc}"
                raise DataSafeHavenConfigError(msg) from exc

        return self._settings

    @property
    def selected(self) -> str:
        if selected := self.settings.get("selected"):
            return selected
        else:
            msg = f"Selected context is not defined in {self.config_file_path}."
            raise DataSafeHavenParameterError(msg)

    @selected.setter
    def selected(self, context_name: str) -> None:
        if context_name in self.settings["contexts"].keys():
            self.settings["selected"] = context_name
            self.logger.info(f"Switched context to {context_name}.")
        else:
            msg = f"Context {context_name} is not defined in {self.config_file_path}."
            raise DataSafeHavenParameterError(msg)

    @property
    def context(self) -> Context:
        if context_dict := self.settings.get("contexts").get(self.selected):
            return Context(**context_dict)
        else:
            msg = f"Context {self.selected} is not defined in {self.config_file_path}."
            raise DataSafeHavenParameterError(msg)

    def update(
        self,
        *,
        admin_group_id: str | None = None,
        location: str | None = None,
        name: str | None = None,
        subscription_name: str | None = None,
    ) -> None:
        context_dict = self.settings.get("contexts").get(self.selected)

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

    def write(self) -> None:
        """Write settings to YAML file"""
        # Create the parent directory if it does not exist then write YAML
        self.config_file_path.parent.mkdir(parents=True, exist_ok=True)

        with open(self.config_file_path, "w", encoding="utf-8") as f_yaml:
            yaml.dump(self.settings, f_yaml, indent=2)
        self.logger.info(
            f"Saved context settings to '[green]{self.config_file_path}[/]'."
        )
