"""Load global and local settings from dotfiles"""
from dataclasses import dataclass
import pathlib

import appdirs
import yaml
from yaml.parser import ParserError

from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.utility import LoggingSingleton


@dataclass
class Context():
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
            azure:
                admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
                location: uksouth
                subscription_name: Data Safe Haven (Acme)
        ...
    """

    def __init__(self) -> None:
        self.logger = LoggingSingleton()

        self._selected: str | None = None
        self._context: Context | None = None

        config_directory = pathlib.Path(
            appdirs.user_config_dir(appname="data_safe_haven")
        ).resolve()
        self.config_file_path = config_directory / "config.yaml"
        self.read()

    def read(self) -> None:
        """Read settings from YAML file"""
        try:
            with open(self.config_file_path, encoding="utf-8") as f_yaml:
                settings = yaml.safe_load(f_yaml)
            if isinstance(settings, dict):
                self.logger.info(
                    f"Reading project settings from '[green]{self.config_file_path}[/]'."
                )
                self._selected = settings.get("selected")
                self._context = Context(**settings.get("contexts").get(self._selected))
        except FileNotFoundError as exc:
            msg = f"Could not find file {self.config_file_path}.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc
        except ParserError as exc:
            msg = f"Could not load settings from {self.config_file_path}.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

    @property
    def selected(self) -> str:
        if not self._selected:
            msg = f"Selected context is not defined in {self.config_file_path}."
            raise DataSafeHavenParameterError(msg)
        return self._selected

    @property
    def context(self) -> Context:
        if not self._context:
            msg = f"Context {self._selected} is not defined in {self.config_file_path}."
            raise DataSafeHavenParameterError(msg)
        return self._context

    def update(
        self,
        *,
        admin_group_id: str | None = None,
        location: str | None = None,
        name: str | None = None,
        subscription_name: str | None = None,
    ) -> None:
        """Overwrite defaults with provided parameters"""
        if admin_group_id:
            self.logger.debug(
                f"Updating '[green]{admin_group_id}[/]' to '{admin_group_id}'."
            )
            self._admin_group_id = admin_group_id
        if location:
            self.logger.debug(f"Updating '[green]{location}[/]' to '{location}'.")
            self._location = location
        if name:
            self.logger.debug(f"Updating '[green]{name}[/]' to '{name}'.")
            self._name = name
        if subscription_name:
            self.logger.debug(
                f"Updating '[green]{subscription_name}[/]' to '{subscription_name}'."
            )
            self._subscription_name = subscription_name

        # Write backend settings to disk (this will trigger errors for uninitialised parameters)
        self.write()

    def write(self) -> None:
        """Write settings to YAML file"""
        settings = {
            "azure": {
                "admin_group_id": self.admin_group_id,
                "location": self.location,
                "subscription_name": self.subscription_name,
            },
            "current": {
                "name": self.name,
            },
        }
        # Create the parent directory if it does not exist then write YAML
        self.config_file_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.config_file_path, "w", encoding="utf-8") as f_yaml:
            yaml.dump(settings, f_yaml, indent=2)
        self.logger.info(
            f"Saved project settings to '[green]{self.config_file_path}[/]'."
        )
