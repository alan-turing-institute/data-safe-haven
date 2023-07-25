"""Provisioning manager for a deployed SRE."""
import pathlib
from typing import Any

from data_safe_haven.external import (
    AzureApi,
    AzureContainerInstance,
    AzurePostgreSQLDatabase,
)
from data_safe_haven.pulumi import PulumiSHMStack, PulumiSREStack
from data_safe_haven.utility import FileReader, Logger


class SREProvisioningManager:
    """Provisioning manager for a deployed SRE."""

    def __init__(
        self,
        available_vm_skus: dict[str, dict[str, Any]],
        shm_stack: PulumiSHMStack,
        sre_name: str,
        sre_stack: PulumiSREStack,
        subscription_name: str,
        timezone: str,
    ):
        super().__init__()
        self.logger = Logger()
        self.resources_path = pathlib.Path(__file__).parent.parent / "resources"
        self.sre_name = sre_name
        self.subscription_name = subscription_name

        # Construct remote desktop parameters
        self.remote_desktop_params = sre_stack.output("remote_desktop")
        self.remote_desktop_params["connection_db_server_password"] = sre_stack.secret("password-user-database-admin")
        self.remote_desktop_params["timezone"] = timezone

        # Construct security group parameters
        self.security_group_params = {
            "dn_base": shm_stack.output("domain_controllers")["ldap_root_dn"],
            "resource_group_name": shm_stack.output("domain_controllers")["resource_group_name"],
            "security_group_names": {
                "admin_security_group_name": sre_stack.output("ldap")["admin_security_group_name"],
                "privileged_user_security_group_name": sre_stack.output("ldap")["privileged_user_security_group_name"],
                "user_security_group_name": sre_stack.output("ldap")["user_security_group_name"],
            },
            "vm_name": shm_stack.output("domain_controllers")["vm_name"],
        }

        # Construct VM parameters
        self.research_desktops = {}
        for idx, vm in enumerate(sre_stack.output("research_desktops")["vm_outputs"]):
            self.research_desktops[f"SRD {idx}"] = {
                "cpus": int(available_vm_skus[vm["sku"]]["vCPUs"]),
                "gpus": int(available_vm_skus[vm["sku"]]["GPUs"]),
                "ip_address": vm["ip_address"],
                "name": vm["name"],
                "ram": int(available_vm_skus[vm["sku"]]["MemoryGB"]),
                "sku": vm["sku"],
            }

    def create_security_groups(self) -> None:
        azure_api = AzureApi(self.subscription_name)
        script = FileReader(self.resources_path / "active_directory" / "add_group.ps1")
        for group_name in self.security_group_params["security_group_names"].values():
            script_parameters = {
                "GroupName": group_name,
                "OuPath": f"OU=Data Safe Haven Security Groups,{self.security_group_params['dn_base']}",
            }
            output = azure_api.run_remote_script(
                self.security_group_params["resource_group_name"],
                script.file_contents(),
                script_parameters,
                self.security_group_params["vm_name"],
            )
            for line in output.split("\n"):
                self.logger.parse(line)

    def restart_remote_desktop_containers(self) -> None:
        # Restart the Guacamole container group
        guacamole_provisioner = AzureContainerInstance(
            self.remote_desktop_params["container_group_name"],
            self.remote_desktop_params["resource_group_name"],
            self.subscription_name,
        )
        guacamole_provisioner.restart(self.remote_desktop_params["container_ip_address"])

    def update_remote_desktop_connections(self) -> None:
        """Update connection information on the Guacamole PostgreSQL server"""
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
                    "disable_copy": self.remote_desktop_params["disable_copy"],
                    "disable_paste": self.remote_desktop_params["disable_paste"],
                    "ip_address": vm_details["ip_address"],
                    "timezone": self.remote_desktop_params["timezone"],
                }
                for vm_identifier, vm_details in self.research_desktops.items()
            ],
            "system_administrator_group_name": self.security_group_params["security_group_names"][
                "admin_security_group_name"
            ],
            "user_group_name": self.security_group_params["security_group_names"]["user_security_group_name"],
        }
        for details in connection_data["connections"]:
            self.logger.info(
                f"Adding connection [bold]{details['connection_name']}[/] at [green]{details['ip_address']}[/]."
            )
        postgres_script_path = pathlib.Path(__file__).parent.parent / "resources" / "remote_desktop" / "postgresql"
        postgres_provisioner.execute_scripts(
            [
                postgres_script_path / "init_db.mustache.sql",
                postgres_script_path / "update_connections.mustache.sql",
            ],
            mustache_values=connection_data,
        )

    def run(self) -> None:
        """Apply SRE configuration"""
        self.create_security_groups()
        self.update_remote_desktop_connections()
        self.restart_remote_desktop_containers()
