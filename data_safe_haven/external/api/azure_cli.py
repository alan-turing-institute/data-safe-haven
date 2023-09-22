"""Interface to the Azure CLI"""
import json
import subprocess
from dataclasses import dataclass
from shutil import which

from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.utility import LoggingSingleton


@dataclass
class AzureCliAccount:
    name: str
    id_: str
    tenant_id: str


class AzureCli:
    """Interface to the Azure CLI"""

    def __init__(self):
        self.logger = LoggingSingleton()

        self.path = which("az")
        if self.path is None:
            msg = "Unable to find Azure CLI executable in your path.\nPlease ensure that Azure CLI is installed"
            raise DataSafeHavenAzureError(msg)

        self._account = None

    @property
    def account(self) -> AzureCliAccount:
        if not self._account:
            try:
                result = subprocess.check_output(
                    [self.path, "account", "show", "--output", "json"],
                    stderr=subprocess.PIPE,
                    encoding="utf8",
                )

                try:
                    result_dict = json.loads(result)
                except json.JSONDecodeError as exc:
                    msg = f"Unable to parse Azure CLI output as JSON.\n{result}"
                    raise DataSafeHavenAzureError(msg) from exc

                self._account = AzureCliAccount(
                    name=result_dict.get("user").get("name"),
                    id_=result_dict.get("id"),
                    tenant_id=result_dict.get("tenantId"),
                )

            except subprocess.CalledProcessError as exc:
                msg = f"Error getting account information from Azure CLI.\n{exc.stderr}"
                raise DataSafeHavenAzureError(msg) from exc

        return self._account
