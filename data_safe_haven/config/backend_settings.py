"""Load global and local settings from dotfiles"""
# Standard library imports
import pathlib
from typing import Dict, Optional

# Third party imports
import yaml

# Local imports
from data_safe_haven.exceptions import DataSafeHavenInputException
from data_safe_haven.utility import Logger, PathType


class BackendSettings:
    """Load global and local settings from dotfiles with structure like the following

    azure:
      admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
      location: uksouth
      subscription_name: Data Safe Haven Development
    shm:
      name: Turing Development
    """

    admin_group_id: str
    location: str
    name: str
    subscription_name: str
    config_file_name: str = ".dshconfig"

    def __init__(
        self,
        admin_group_id: Optional[str] = None,
        location: Optional[str] = None,
        name: Optional[str] = None,
        subscription_name: Optional[str] = None,
    ):
        super().__init__()
        self.logger = Logger()
        # Load local dotfile settings (if any)
        local_values: Dict[str, str] = {}
        local_dotfile = pathlib.Path.cwd() / self.config_file_name
        try:
            if local_dotfile.exists():
                local_values = self.read(local_dotfile)
        except Exception as exc:
            raise DataSafeHavenInputException(
                f"Could not load settings from YAML file '{local_dotfile}'.\n{str(exc)}"
            ) from exc

        # Request any missing parameters
        while not admin_group_id:
            admin_group_id = (
                local_values["admin_group_id"]
                if "admin_group_id" in local_values
                else self.logger.ask(
                    "Please enter the ID for an Azure group containing all administrators:",
                )
            )
        self.admin_group_id = admin_group_id
        while not location:
            location = (
                local_values["location"]
                if "location" in local_values
                else self.logger.ask(
                    "Please enter the Azure location to deploy resources into:"
                )
            )
        self.location = location
        while not name:
            name = (
                local_values["name"]
                if "name" in local_values
                else self.logger.ask(
                    "Please enter the name for this Data Safe Haven deployment:"
                )
            )
        self.name = name
        while not subscription_name:
            subscription_name = (
                local_values["subscription_name"]
                if "subscription_name" in local_values
                else self.logger.ask(
                    "Please enter the Azure subscription to deploy resources into:",
                )
            )
        self.subscription_name = subscription_name

    def read(self, yaml_file: PathType) -> Dict[str, str]:
        """Read settings from YAML file"""
        values = {}
        with open(pathlib.Path(yaml_file), "r", encoding="utf-8") as f_yaml:
            settings = yaml.safe_load(f_yaml)
        if isinstance(settings, dict):
            if admin_group_id := settings.get("azure", {}).get("admin_group_id", None):
                values["admin_group_id"] = admin_group_id
            if location := settings.get("azure", {}).get("location", None):
                values["location"] = location
            if name := settings.get("shm", {}).get("name", None):
                values["name"] = name
            if subscription_name := settings.get("azure", {}).get(
                "subscription_name", None
            ):
                values["subscription_name"] = subscription_name
        return values

    def write(self, directory: PathType) -> pathlib.Path:
        """Write settings to YAML file"""
        settings = {
            "shm": {
                "name": self.name,
            },
            "azure": {
                "admin_group_id": self.admin_group_id,
                "location": self.location,
                "subscription_name": self.subscription_name,
            },
        }
        filepath = (pathlib.Path(directory) / self.config_file_name).resolve()
        with open(filepath, "w", encoding="utf-8") as f_yaml:
            yaml.dump(settings, f_yaml, indent=2)
        return filepath
