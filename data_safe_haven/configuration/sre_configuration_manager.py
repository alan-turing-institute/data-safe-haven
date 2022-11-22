"""Backend for a Data Safe Haven environment"""
# Standard library imports
import pathlib

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.external.interface import AzureContainerInstance, AzurePostgreSQLDatabase
from data_safe_haven.external.api import AzureApi
from data_safe_haven.helpers import FileReader
from data_safe_haven.mixins import LoggingMixin


class SREConfigurationManager(LoggingMixin):
    """Configuration manager for a deployed SRE."""

    def __init__(
        self,
        config: Config,
        sre_name: str,
    ):
        super().__init__()
        self.resources_path = pathlib.Path(__file__).parent.parent / "resources"
        self.sre_name = sre_name
        self.subscription_name = config.subscription_name

        # Construct remote desktop parameters
        self.remote_desktop_params = dict(config.sre[sre_name].remote_desktop)
        self.remote_desktop_params["connection_db_server_password"] = config.get_secret(
            config.sre[self.sre_name].remote_desktop[
                "connection_db_server_admin_password_secret"
            ]
        )
        self.remote_desktop_params["timezone"] = config.shm.timezone

        # Construct security group parameters
        self.security_group_params = {
            "dn_base": f"DC={config.shm.fqdn.replace('.',',DC=')}",
            "resource_group_name": config.shm.domain_controllers.resource_group_name,
            "group_name": config.sre[self.sre_name].security_group_name,
            "vm_name": config.shm.domain_controllers.vm_name,
        }

        # Construct VM parameters
        self.research_desktops = dict(config.sre[sre_name].research_desktops)

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
        for line in output.split("\n"):
            self.parse_as_log(line)

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
                    "connection_name": f"{vm_details['sku']} [{vm_details['cpus']} CPU(s), {vm_details['gpus']} GPU(s), {vm_details['ram']} GB RAM] ({vm_name})",
                    "disable_copy": (not self.remote_desktop_params["allow_copy"]),
                    "disable_paste": (not self.remote_desktop_params["allow_paste"]),
                    "ip_address": vm_details["ip_address"],
                    "timezone": self.remote_desktop_params["timezone"],
                }
                for vm_name, vm_details in self.research_desktops.items()
            ]
        }
        for details in connection_data["connections"]:
            self.info(
                f"Adding connection {details['connection_name']} at {details['ip_address']}"
            )
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

    def restart_remote_desktop_containers(self) -> None:
        # Restart the Guacamole container group
        guacamole_provisioner = AzureContainerInstance(
            self.remote_desktop_params["container_group_name"],
            self.remote_desktop_params["resource_group_name"],
            self.subscription_name,
        )
        guacamole_provisioner.restart(
            self.remote_desktop_params["container_ip_address"]
        )
