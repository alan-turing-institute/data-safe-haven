"""Load global and local settings from dotfiles"""
# Standard library imports
import pathlib
from typing import Optional

# Third party imports
import appdirs
import yaml

# Local imports
from data_safe_haven.exceptions import DataSafeHavenParameterException
from data_safe_haven.utility import Logger


class BackendSettings:
    """Load global and local settings from dotfiles with structure like the following

    azure:
      admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
      location: uksouth
      subscription_name: Data Safe Haven Development
    current:
      name: Turing Development
    """

    def __init__(
        self,
    ) -> None:
        # Define instance variables
        self._admin_group_id: Optional[str] = None
        self._location: Optional[str] = None
        self._name: Optional[str] = None
        self._subscription_name: Optional[str] = None
        self.logger = Logger()

        # Load previous backend settings (if any)
        self.config_directory = pathlib.Path(
            appdirs.user_config_dir("data_safe_haven")
        ).resolve()
        self.config_file_path = self.config_directory / "config.yaml"
        self.read()

    def update(
        self,
        *,
        admin_group_id: Optional[str] = None,
        location: Optional[str] = None,
        name: Optional[str] = None,
        subscription_name: Optional[str] = None,
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
            raise DataSafeHavenParameterException(
                "Azure administrator group not provided: use '[bright_cyan]--admin-group[/]' / '[green]-a[/]' to do so."
            )
        return self._admin_group_id

    @property
    def location(self) -> str:
        if not self._location:
            raise DataSafeHavenParameterException(
                "Azure location not provided: use '[bright_cyan]--location[/]' / '[green]-l[/]' to do so."
            )
        return self._location

    @property
    def name(self) -> str:
        if not self._name:
            raise DataSafeHavenParameterException(
                "Data Safe Haven deployment name not provided: use '[bright_cyan]--deployment-name[/]' / '[green]-d[/]' to do so."
            )
        return self._name

    @property
    def subscription_name(self) -> str:
        if not self._subscription_name:
            raise DataSafeHavenParameterException(
                "Azure subscription not provided: use '[bright_cyan]--subscription[/]' / '[green]-s[/]' to do so."
            )
        return self._subscription_name

    def read(self) -> None:
        """Read settings from YAML file"""
        if self.config_file_path.exists():
            with open(self.config_file_path, "r", encoding="utf-8") as f_yaml:
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
