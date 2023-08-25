"""Provisioning manager for a deployed SHM."""
from data_safe_haven.external import AzureApi
from data_safe_haven.infrastructure import PulumiSHMStack


class SHMProvisioningManager:
    """Provisioning manager for a deployed SHM."""

    def __init__(
        self,
        subscription_name: str,
        stack: PulumiSHMStack,
    ):
        super().__init__()
        self.subscription_name = subscription_name
        domain_controllers_resource_group_name = stack.output("domain_controllers")[
            "resource_group_name"
        ]
        domain_controllers_vm_name = stack.output("domain_controllers")["vm_name"]

        # Construct DC restart parameters
        self.dc_restart_params = {
            "resource_group_name": domain_controllers_resource_group_name,
            "vm_name": domain_controllers_vm_name,
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
