"""Interface to the Azure CLI"""
import subprocess
from typing import Any

from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.utility import LoggingSingleton


class AzureCli:
    """Interface to the Azure CLI"""

    def __init__(self, *args: Any, **kwargs: Any):
        super().__init__(*args, **kwargs)
        self.logger = LoggingSingleton()

    def login(self) -> None:
        """Force log in via the Azure CLI"""
        try:
            self.logger.debug("Attempting to login using Azure CLI.")
            # We do not use `check` in subprocess as this raises a CalledProcessError
            # which would break the loop. Instead we check the return code of
            # `az account show` which will be 0 on success.
            while True:
                # Check whether we are already logged in
                process = subprocess.run(
                    ["az", "account", "show"], capture_output=True, check=False
                )
                if process.returncode == 0:
                    break
                # Note that subprocess.run will block until the process terminates so
                # we need to print the guidance first.
                self.logger.info(
                    "Please login in your web browser at [bold]https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize[/]."
                )
                self.logger.info(
                    "If no web browser is available, please run [bold]az login --use-device-code[/] in a command line window."
                )
                # Attempt to log in at the command line
                process = subprocess.run(
                    ["az", "login"], capture_output=True, check=False
                )
        except FileNotFoundError as exc:
            msg = f"Please ensure that the Azure CLI is installed.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc
