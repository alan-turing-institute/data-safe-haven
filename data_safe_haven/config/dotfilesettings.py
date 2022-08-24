"""Load global and local settings from dotfiles"""
# Standard library imports
import pathlib
import re

# Third party imports
import yaml

# Local imports
from data_safe_haven import __version__
from data_safe_haven.exceptions import DataSafeHavenInputException


class DotFileSettings:
    """Load global and local settings from dotfiles with structure like the following

    dsh:
      name: Turing Development
    azure:
        subscription_name: Data Safe Haven Development
        admin_group_id: 347c68cb-261f-4a3e-ac3e-6af860b5fec9
        location: uksouth
    """

    admin_group_id: str = None
    location: str = None
    name: str = None
    subscription_name: str = None

    def __init__(
        self, admin_group_id: str, location: str, name: str, subscription_name: str
    ):
        # Override with global dotfile settings (if any)
        try:
            global_dotfile = pathlib.Path.home() / ".dshbackend.yaml"
            if global_dotfile.exists():
                with open(pathlib.Path(global_dotfile), "r") as f_yaml:
                    settings = yaml.safe_load(f_yaml)
                    self.admin_group_id = settings.get("azure", {}).get(
                        "admin_group_id", self.admin_group_id
                    )
                    self.location = settings.get("azure", {}).get(
                        "location", self.location
                    )
                    self.name = settings.get("dsh", {}).get("name", self.name)
                    self.subscription_name = settings.get("azure", {}).get(
                        "subscription_name", self.subscription_name
                    )
        except Exception as exc:
            raise DataSafeHavenInputException(
                f"Could not load settings from YAML file '{global_dotfile}'"
            ) from exc

        try:
            # Override with local dotfile settings (if any)
            local_dotfile = pathlib.Path.cwd() / ".dshbackend.yaml"
            if local_dotfile.exists():
                with open(pathlib.Path(local_dotfile), "r") as f_yaml:
                    settings = yaml.safe_load(f_yaml)
                    self.admin_group_id = settings.get("azure", {}).get(
                        "admin_group_id", self.admin_group_id
                    )
                    self.location = settings.get("azure", {}).get(
                        "location", self.location
                    )
                    self.name = settings.get("dsh", {}).get("name", self.name)
                    self.subscription_name = settings.get("azure", {}).get(
                        "subscription_name", self.subscription_name
                    )
        except Exception as exc:
            raise DataSafeHavenInputException(
                f"Could not load settings from YAML file '{local_dotfile}'"
            ) from exc

        # Override with command-line settings (if any)
        if admin_group_id:
            self.admin_group_id = admin_group_id
        if location:
            self.location = location
        if name:
            self.name = name
        if subscription_name:
            self.subscription_name = subscription_name

        if not all(
            [self.admin_group_id, self.location, self.name, self.subscription_name]
        ):
            raise DataSafeHavenInputException(
                f"Not enough information to initialise Data Safe Haven. Please provide subscription_name and location in one of the following ways\n"
                + "- in ~/.dshbackend.yaml\n"
                + "- in $PWD/.dshbackend.yaml\n"
                + "- via command line arguments"
            )
