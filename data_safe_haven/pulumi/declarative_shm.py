"""Deploy Data Safe Haven Management environment with Pulumi"""
# Third party imports
import pulumi
from pulumi_azure_native import resources

# Local imports
from .components.shm_networking import SHMNetworkingComponent, SHMNetworkingProps
from .components.shm_secrets import SHMSecretsComponent, SHMSecretsProps
from .components.shm_domain_controllers import (
    SHMDomainControllersComponent,
    SHMDomainControllersProps,
)
from .components.shm_monitoring import SHMMonitoringComponent, SHMMonitoringProps


class DeclarativeSHM:
    """Deploy Data Safe Haven Management environment with Pulumi"""

    def __init__(self, config):
        self.cfg = config

    def run(self):
        # Load pulumi configuration secrets
        self.secrets = pulumi.Config()

        # Define resource groups
        rg_networking = resources.ResourceGroup(
            "rg_networking",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-shm-{self.cfg.shm.name}-networking",
        )
        rg_monitoring = resources.ResourceGroup(
            "rg_monitoring",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-shm-{self.cfg.shm.name}-monitoring",
        )
        rg_storage = resources.ResourceGroup(
            "rg_storage",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-shm-{self.cfg.shm.name}-storage",
        )
        rg_users = resources.ResourceGroup(
            "rg_users",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-shm-{self.cfg.shm.name}-users",
        )

        # Deploy SHM networking
        networking = SHMNetworkingComponent(
            self.cfg.shm.name,
            SHMNetworkingProps(
                fqdn=self.cfg.shm.fqdn,
                resource_group_name=rg_networking.name,
            ),
        )

        # Deploy SHM secrets
        secrets = SHMSecretsComponent(
            self.cfg.shm.name,
            SHMSecretsProps(
                admin_group_id=self.cfg.azure.admin_group_id,
                location=self.cfg.azure.location,
                resource_group_name=rg_storage.name,
                tenant_id=self.cfg.azure.tenant_id,
            ),
        )

        # Deploy SHM monitoring
        automation = SHMMonitoringComponent(
            self.cfg.shm.name,
            SHMMonitoringProps(
                location=self.cfg.azure.location,
                resource_group_name=rg_monitoring.name,
            ),
        )

        # Deploy firewall

        # Deploy update servers

        # Deploy domain controllers

        domain_controllers = SHMDomainControllersComponent(
            self.cfg.shm.name,
            SHMDomainControllersProps(
                admin_password=self.secrets.require("vm-password-primary-dc"),
                ip_address_private=str(networking.subnet_users_iprange.available()[0]),
                location=self.cfg.azure.location,
                resource_group_name=rg_users.name,
                subnet_name="UsersSubnet",
                virtual_network_name=networking.virtual_network.name,
                virtual_network_resource_group_name=networking.resource_group_name,
            ),
        )
