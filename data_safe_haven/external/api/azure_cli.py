"""Interface to the Azure CLI"""
import subprocess
from typing import Any

from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.utility import Logger


class AzureCli:
    """Interface to the Azure CLI"""

    def __init__(self, *args: Any, **kwargs: Any):
        super().__init__(*args, **kwargs)
        self.logger = Logger()

    def login(self) -> None:
        """Force log in via the Azure CLI"""
        try:
            self.logger.debug("Attempting to login using Azure CLI.")
            while True:
                process = subprocess.run(["az", "account", "show"], capture_output=True)
                if process.returncode == 0:
                    break
                self.logger.info(
                    "Please login in your web browser at https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize."
                )
                self.logger.info(
                    "If no web browser is available, please run `az login --use-device-code` in a command line window."
                )
                subprocess.run(["az", "login"], capture_output=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            msg = f"Please ensure that the Azure CLI is installed.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc
