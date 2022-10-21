"""Backend for a Data Safe Haven environment"""
# Standard library imports
import pathlib
from typing import Dict, Sequence, Tuple

# Local imports
from data_safe_haven.mixins import LoggingMixin
from .components import ContainerProvisioner, PostgreSQLProvisioner


class SREConfigurationManager(LoggingMixin):
    """Configuration manager for a deployed SRE."""

    def __init__(
        self,
        connection_db_server_password: str,
        remote_desktop_params: Dict[str, str],
        subscription_name: str,
        vm_params: Sequence[Tuple],
    ):
        super().__init__()
        self.connection_db_server_password = connection_db_server_password
        self.remote_desktop_params = remote_desktop_params
        self.subscription_name = subscription_name
        self.vm_params = vm_params

    def apply_configuration(self) -> None:
        """Apply SRE configuration"""
        self.update_remote_desktop_connections()
        self.restart_remote_desktop_containers()

    def update_remote_desktop_connections(self) -> None:
        """Update connection information on the Guacamole PostgreSQL server"""
        postgres_provisioner = PostgreSQLProvisioner(
            self.remote_desktop_params["connection_db_name"],
            self.connection_db_server_password,
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
