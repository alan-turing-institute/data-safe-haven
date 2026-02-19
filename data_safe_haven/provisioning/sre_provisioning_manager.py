"""Provisioning manager for a deployed SRE."""

import pathlib
from typing import Any

from data_safe_haven.external import (
    AzureContainerInstance,
    AzurePostgreSQLDatabase,
    AzureSdk,
)
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.logging import get_logger
from data_safe_haven.types import AzureLocation, AzureSubscriptionName


class SREProvisioningManager:
    """Provisioning manager for a deployed SRE."""

    def __init__(
        self,
        location: AzureLocation,
        sre_name: str,
        sre_stack: SREProjectManager,
        subscription_name: AzureSubscriptionName,
        timezone: str,
    ):
        self._available_vm_skus: dict[str, dict[str, Any]] | None = None
        self.location = location
        self.logger = get_logger()
        self.sre_name = sre_name
        self.subscription_name = subscription_name

        # Read secrets from key vault
        keyvault_name = sre_stack.output("data")["key_vault_name"]
        user_database_secret_name = sre_stack.output("data")[
            "password_user_database_admin_secret"
        ]
        azure_sdk = AzureSdk(self.subscription_name)
        connection_user_database_server_password = azure_sdk.get_keyvault_secret(
            keyvault_name, user_database_secret_name
        )

        # Construct remote desktop parameters
        self.remote_desktop_params = sre_stack.output("remote_desktop")
        self.remote_desktop_params["connection_db_server_password"] = (
            connection_user_database_server_password
        )
        self.remote_desktop_params["timezone"] = timezone

        # Construct software repositories parameters
        nexus_database_secret_name = sre_stack.output("data")[
            "password_nexus_database_admin_secret"
        ]
        self.software_repository_params: dict[str, str] | None = sre_stack.output(
            "software_repositories"
        )
        if self.software_repository_params:
            connection_nexus_database_server_password = azure_sdk.get_keyvault_secret(
                keyvault_name, nexus_database_secret_name
            )
            self.software_repository_params["connection_db_server_password"] = (
                connection_nexus_database_server_password
            )

        # Construct security group parameters
        self.security_group_params = dict(sre_stack.output("ldap"))

        # Construct VM parameters
        self.workspaces = {}
        for idx, vm in enumerate(sre_stack.output("workspaces")["vm_outputs"], start=1):
            self.workspaces[f"Workspace {idx}"] = {
                "cpus": int(self.available_vm_skus[vm["sku"]]["vCPUs"]),
                "gpus": int(self.available_vm_skus[vm["sku"]]["GPUs"]),
                "ip_address": vm["ip_address"],
                "name": vm["name"],
                "ram": int(self.available_vm_skus[vm["sku"]]["MemoryGB"]),
                "sku": vm["sku"],
            }

    @property
    def available_vm_skus(self) -> dict[str, dict[str, Any]]:
        """Load available VM SKUs for this region"""
        if not self._available_vm_skus:
            azure_sdk = AzureSdk(self.subscription_name)
            self._available_vm_skus = azure_sdk.list_available_vm_skus(self.location)
        return self._available_vm_skus

    def restart_remote_desktop_containers(self) -> None:
        """Restart the Guacamole container group"""
        guacamole_provisioner = AzureContainerInstance(
            self.remote_desktop_params["container_group_name"],
            self.remote_desktop_params["resource_group_name"],
            self.subscription_name,
        )
        guacamole_provisioner.restart()

    def restart_software_repositories_containers(self) -> None:
        """Restart the Software Repositories container group"""
        if self.software_repository_params:
            software_repositories_provisioner = AzureContainerInstance(
                self.software_repository_params["container_group_name"],
                self.software_repository_params["resource_group_name"],
                self.subscription_name,
            )
            software_repositories_provisioner.restart()

    def initialise_software_repository_database(self) -> None:
        """Configures a PostgreSQL database for the Nexus container"""
        if self.software_repository_params:
            self.logger.info("Configuring software repository database.")

            postgres_provisioner = AzurePostgreSQLDatabase(
                self.software_repository_params["connection_db_name"],
                self.software_repository_params["connection_db_server_password"],
                self.software_repository_params["connection_db_server_name"],
                self.software_repository_params["resource_group_name"],
                self.subscription_name,
            )

            postgres_script_path = (
                pathlib.Path(__file__).parent.parent
                / "resources"
                / "software_repositories"
                / "postgresql"
            )

            mustache_values: dict[str, str] = {
                "nexus_password": self.software_repository_params[
                    "connection_db_server_password"
                ]
            }
            postgres_provisioner.execute_scripts(
                [
                    postgres_script_path / "init_db.mustache.sql",
                ],
                mustache_values=mustache_values,
            )

    def update_remote_desktop_connections(self) -> None:
        """Update connection information on the Guacamole PostgreSQL server"""
        self.logger.info("Configuring remote desktop connections database.")
        postgres_provisioner = AzurePostgreSQLDatabase(
            self.remote_desktop_params["connection_db_name"],
            self.remote_desktop_params["connection_db_server_password"],
            self.remote_desktop_params["connection_db_server_name"],
            self.remote_desktop_params["resource_group_name"],
            self.subscription_name,
        )
        connection_data = {
            "connections": [
                {
                    "connection_name": (
                        f"{vm_identifier} [{vm_details['cpus']} CPU(s),"
                        f" {vm_details['gpus']} GPU(s), {vm_details['ram']} GB RAM]"
                    ),
                    "disable_copy": str(
                        self.remote_desktop_params["disable_copy"]
                    ).lower(),
                    "disable_paste": str(
                        self.remote_desktop_params["disable_paste"]
                    ).lower(),
                    "ip_address": vm_details["ip_address"],
                    "timezone": self.remote_desktop_params["timezone"],
                }
                for vm_identifier, vm_details in self.workspaces.items()
            ],
            "system_administrator_group_name": self.security_group_params[
                "admin_group_name"
            ],
            "user_group_name": self.security_group_params["user_group_name"],
        }
        for details in connection_data["connections"]:
            self.logger.info(
                f"Adding connection [bold]{details['connection_name']}[/] at [green]{details['ip_address']}[/]."
            )
        postgres_script_path = (
            pathlib.Path(__file__).parent.parent
            / "resources"
            / "remote_desktop"
            / "postgresql"
        )
        postgres_provisioner.execute_scripts(
            [
                postgres_script_path / "init_db.mustache.sql",
                postgres_script_path / "update_connections.mustache.sql",
            ],
            mustache_values=connection_data,
        )

    def run(self) -> None:
        """Apply SRE configuration"""

        # Configuring Guacamole
        self.update_remote_desktop_connections()
        self.restart_remote_desktop_containers()

        # Configuring software repositories
        self.initialise_software_repository_database()
        self.restart_software_repositories_containers()
