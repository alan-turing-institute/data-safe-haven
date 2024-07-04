"""Interface to the Azure CLI"""

import json
import subprocess
from dataclasses import dataclass
from shutil import which

import typer

from data_safe_haven import console
from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.logging import get_logger
from data_safe_haven.singleton import Singleton


@dataclass
class AzureCliAccount:
    """Dataclass for Azure CLI Account details"""

    name: str
    id_: str
    tenant_id: str
    tenant_name: str


class AzureCliSingleton(metaclass=Singleton):
    """Interface to the Azure CLI"""

    def __init__(self) -> None:
        self.logger = get_logger()

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
                result_dict = json.loads(result)
            except subprocess.CalledProcessError as exc:
                self.logger.error(str(exc.stderr).replace("ERROR:", "").strip())
                msg = "Error getting account information from Azure CLI."
                raise DataSafeHavenAzureError(msg) from exc
            except json.JSONDecodeError as exc:
                msg = f"Unable to parse Azure CLI output as JSON.\n{result}"
                raise DataSafeHavenAzureError(msg) from exc

            self._account = AzureCliAccount(
                name=result_dict.get("user").get("name"),
                id_=result_dict.get("id"),
                tenant_id=result_dict.get("tenantId"),
                tenant_name=result_dict.get("tenantDisplayName"),
            )

        return self._account

    def confirm(self) -> None:
        """Prompt user to confirm the Azure CLI account is correct"""
        if self._confirmed:
            return None

        account = self.account
        self.logger.info(
            "You are currently logged into the [blue]Azure CLI[/] with the following details:"
        )
        self.logger.info(f"... user: [green]{account.name}[/] ({account.id_})")
        self.logger.info(
            f"... tenant: [green]{account.tenant_name}[/] ({account.tenant_id})"
        )
        if not console.confirm(
            "Is this the Azure account you expect?", default_to_yes=False
        ):
            self.logger.error(
                "Please use `az login` to connect to the correct Azure CLI account"
            )
            raise typer.Exit(1)

        self._confirmed = True

    def group_id_from_name(self, group_name: str) -> str:
        """Get ID for an Entra ID group that this user is permitted to view."""
        try:
            result = subprocess.check_output(
                [self.path, "ad", "group", "list", "--display-name", group_name],
                stderr=subprocess.PIPE,
                encoding="utf8",
            )
        except subprocess.CalledProcessError as exc:
            msg = f"Error reading groups from Azure CLI.\n{exc.stderr}"
            raise DataSafeHavenAzureError(msg) from exc

        try:
            result_dict = json.loads(result)
            return str(result_dict[0]["id"])
        except json.JSONDecodeError as exc:
            msg = f"Unable to parse Azure CLI output as JSON.\n{result}"
            raise DataSafeHavenAzureError(msg) from exc
        except (IndexError, KeyError) as exc:
            msg = f"Group '{group_name}' was not found in Azure CLI."
            raise DataSafeHavenAzureError(msg) from exc

    def subscription_id(self, subscription_name: str) -> str:
        """Get subscription ID from an Azure subscription name."""
        try:
            result = subprocess.check_output(
                [
                    self.path,
                    "account",
                    "subscription",
                    "list",
                    "--query",
                    f"[?displayName == '{subscription_name}']",
                ],
                stderr=subprocess.PIPE,
                encoding="utf8",
            )
            result_dict = json.loads(result)
            return str(result_dict[0]["subscriptionId"])
        except subprocess.CalledProcessError as exc:
            self.logger.critical(exc.stderr)
            msg = "Error reading subscriptions from Azure CLI."
            raise DataSafeHavenAzureError(msg) from exc
        except json.JSONDecodeError as exc:
            msg = "Unable to parse Azure CLI output as JSON."
            raise DataSafeHavenAzureError(msg) from exc
        except (IndexError, KeyError) as exc:
            msg = f"Subscription '{subscription_name}' was not found in Azure CLI."
            raise DataSafeHavenAzureError(msg) from exc
