"""Provisioning manager for a deployed SHM."""
# Local imports
from data_safe_haven.config import Config
from data_safe_haven.external.api import AzureApi
from data_safe_haven.mixins import LoggingMixin


class SHMProvisioningManager(LoggingMixin):
    """Provisioning manager for a deployed SHM."""

    def __init__(
        self,
        config: Config,
    ):
        super().__init__()
        self.subscription_name = config.subscription_name

        # Construct DC restart parameters
        self.dc_restart_params = {
            "resource_group_name": config.shm.domain_controllers["resource_group_name"],
            "vm_name": config.shm.domain_controllers["vm_name"],
        }

    def restart_domain_controllers(self) -> None:
        azure_api = AzureApi(self.subscription_name)
        azure_api.restart_virtual_machine(
            self.dc_restart_params["resource_group_name"],
            self.dc_restart_params["vm_name"],
        )

    def run(self) -> None:
        """Apply SHM configuration"""
        self.restart_domain_controllers()
