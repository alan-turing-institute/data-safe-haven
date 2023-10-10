"""Load global and local settings from dotfiles"""
import pathlib

import appdirs
import yaml
from yaml.parser import ParserError

from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.utility import LoggingSingleton


class BackendSettings:
    """Load global and local settings from dotfiles with structure like the following

    azure:
      admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
      location: uksouth
      subscription_name: Data Safe Haven (Acme)
    current:
      name: Acme Deployment
    """

    def __init__(
        self,
    ) -> None:
        # Define instance variables
        self._admin_group_id: str | None = None
        self._location: str | None = None
        self._name: str | None = None
        self._subscription_name: str | None = None
        self.logger = LoggingSingleton()

        # Load previous backend settings (if any)
        self.config_directory = pathlib.Path(
            appdirs.user_config_dir(appname="data_safe_haven")
        ).resolve()
        self.config_file_path = self.config_directory / "config.yaml"
        self.read()

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

    @property
    def admin_group_id(self) -> str:
        if not self._admin_group_id:
            msg = "Azure administrator group not provided: use '[bright_cyan]--admin-group[/]' / '[green]-a[/]' to do so."
            raise DataSafeHavenParameterError(msg)
        return self._admin_group_id

    @property
    def location(self) -> str:
        if not self._location:
            msg = "Azure location not provided: use '[bright_cyan]--location[/]' / '[green]-l[/]' to do so."
            raise DataSafeHavenParameterError(msg)
        return self._location

    @property
    def name(self) -> str:
        if not self._name:
            msg = (
                "Data Safe Haven deployment name not provided:"
                " use '[bright_cyan]--name[/]' / '[green]-n[/]' to do so."
            )
            raise DataSafeHavenParameterError(msg)
        return self._name

    @property
    def subscription_name(self) -> str:
        if not self._subscription_name:
            msg = "Azure subscription not provided: use '[bright_cyan]--subscription[/]' / '[green]-s[/]' to do so."
            raise DataSafeHavenParameterError(msg)
        return self._subscription_name

    def read(self) -> None:
        """Read settings from YAML file"""
        try:
            if self.config_file_path.exists():
                with open(self.config_file_path, encoding="utf-8") as f_yaml:
                    settings = yaml.safe_load(f_yaml)
                if isinstance(settings, dict):
                    self.logger.info(
                        f"Reading project settings from '[green]{self.config_file_path}[/]'."
                    )
                    if admin_group_id := settings.get("azure", {}).get(
                        "admin_group_id", None
                    ):
                        self._admin_group_id = admin_group_id
                    if location := settings.get("azure", {}).get("location", None):
                        self._location = location
                    if name := settings.get("current", {}).get("name", None):
                        self._name = name
                    if subscription_name := settings.get("azure", {}).get(
                        "subscription_name", None
                    ):
                        self._subscription_name = subscription_name
        except ParserError as exc:
            msg = f"Could not load settings from {self.config_file_path}.\n{exc}"
            raise DataSafeHavenConfigError(msg) from exc

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
