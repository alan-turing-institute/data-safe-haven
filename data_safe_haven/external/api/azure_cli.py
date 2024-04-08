"""Interface to the Azure CLI"""

import json
import subprocess
from dataclasses import dataclass
from shutil import which

import typer

from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.utility import LoggingSingleton, Singleton


@dataclass
class AzureCliAccount:
    """Dataclass for Azure CLI Account details"""

    name: str
    id_: str
    tenant_id: str


class AzureCliSingleton(metaclass=Singleton):
    """Interface to the Azure CLI"""

    def __init__(self) -> None:
        self.logger = LoggingSingleton()

        path = which("az")
        if path is None:
            msg = "Unable to find Azure CLI executable in your path.\nPlease ensure that Azure CLI is installed"
            raise DataSafeHavenAzureError(msg)
        self.path = path

        self._account: AzureCliAccount | None = None
        self._confirmed = False

    @property
    def account(self) -> AzureCliAccount:
        if not self._account:
            try:
                result = subprocess.check_output(
                    [self.path, "account", "show", "--output", "json"],
                    stderr=subprocess.PIPE,
                    encoding="utf8",
                )
            except subprocess.CalledProcessError as exc:
                msg = f"Error getting account information from Azure CLI.\n{exc.stderr}"
                raise DataSafeHavenAzureError(msg) from exc

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

        return self._account

    def confirm(self) -> None:
        """Prompt user to confirm the Azure CLI account is correct"""
        if self._confirmed:
            return None

        account = self.account
        self.logger.info(f"Azure user: {account.name} ({account.id_})")
        self.logger.info(f"Azure tenant ID: {account.tenant_id})")
        if not self.logger.confirm(
            "Is this the Azure account you expect?", default_to_yes=False
        ):
            self.logger.error(
                "Please use `az login` to connect to the correct Azure CLI account"
            )
            raise typer.Exit(1)

        self._confirmed = True
