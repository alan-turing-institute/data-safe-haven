"""Backend for a Data Safe Haven environment"""
# Standard library imports
import pathlib
from typing import Dict, Sequence, Tuple

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.external import AzureApi
from data_safe_haven.helpers import FileReader
from data_safe_haven.mixins import LoggingMixin
from .components import ContainerProvisioner, PostgreSQLProvisioner


class SREConfigurationManager(LoggingMixin):
    """Configuration manager for a deployed SRE."""

    def __init__(
        self,
        config: Config,
        connection_db_server_password: str,
        sre_safe_name: str,
    ):
        super().__init__()
        self.resources_path = pathlib.Path(__file__).parent.parent / "resources"
        self.sre_name = sre_safe_name
        self.subscription_name = config.subscription_name

        # Construct remote desktop parameters
        self.remote_desktop_params = dict(config.sre[sre_safe_name].remote_desktop)
        self.remote_desktop_params[
            "connection_db_server_password"
        ] = connection_db_server_password
        self.remote_desktop_params["timezone"] = config.shm.timezone

        # Construct security group parameters
        self.security_group_params = {
            "dn_base": f"DC={config.shm.fqdn.replace('.',',DC=')}",
            "resource_group_name": config.shm.domain_controllers.resource_group_name,
            "group_name": f"Data Safe Haven Users SRE {self.sre_name}",
            "vm_name": config.shm.domain_controllers.vm_name,
        }

        # Construct VM parameters
        self.vm_params = dict(config.sre[sre_safe_name].vm_details)

    def apply_configuration(self) -> None:
        """Apply SRE configuration"""
        self.create_security_group()
        self.update_remote_desktop_connections()
        self.restart_remote_desktop_containers()

    def create_security_group(self) -> None:
        azure_api = AzureApi(self.subscription_name)
        script = FileReader(self.resources_path / "active_directory" / "add_group.ps1")
        script_parameters = {
            "GroupName": self.security_group_params["group_name"],
            "OuPath": f"OU=Data Safe Haven Security Groups,{self.security_group_params['dn_base']}",
        }
        output = azure_api.run_remote_script(
            self.security_group_params["resource_group_name"],
            script.file_contents(),
            script_parameters,
            self.security_group_params["vm_name"],
        )
        print(output)

    def update_remote_desktop_connections(self) -> None:
        """Update connection information on the Guacamole PostgreSQL server"""
        postgres_provisioner = PostgreSQLProvisioner(
            self.remote_desktop_params["connection_db_name"],
            self.remote_desktop_params["connection_db_server_password"],
            self.remote_desktop_params["connection_db_server_name"],
            self.remote_desktop_params["resource_group_name"],
            self.subscription_name,
        )
        connection_data = {
            "connections": [
                {
                    "connection_name": connection,
                    "disable_copy": (not self.remote_desktop_params["allow_copy"]),
                    "disable_paste": (not self.remote_desktop_params["allow_paste"]),
                    "ip_address": ip_address,
                    "timezone": self.remote_desktop_params["timezone"],
                }
                for (connection, ip_address) in self.vm_params
            ]
        }
        postgres_script_path = (
            pathlib.Path(__file__).parent.parent
            / "resources"
            / "remote_desktop"
            / "postgresql"
        )
        postgres_provisioner.execute_scripts(
            [
                postgres_script_path / "init_db.sql",
                postgres_script_path / "update_connections.mustache.sql",
            ],
            mustache_values=connection_data,
        )

    def restart_remote_desktop_containers(self):
        # Restart the Guacamole container group
        guacamole_provisioner = ContainerProvisioner(
            self.remote_desktop_params["container_group_name"],
            self.remote_desktop_params["resource_group_name"],
            self.subscription_name,
        )
        guacamole_provisioner.restart(
            self.remote_desktop_params["container_ip_address"]
        )
