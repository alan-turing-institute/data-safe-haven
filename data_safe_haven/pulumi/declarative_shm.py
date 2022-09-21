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

    def __init__(self, config, stack_name):
        self.cfg = config
        self.stack_name = stack_name

    def run(self):
        # Load pulumi configuration secrets
        self.secrets = pulumi.Config()

        # Define resource groups
        rg_networking = resources.ResourceGroup(
            "rg_networking",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-{self.stack_name}-networking",
        )
        rg_monitoring = resources.ResourceGroup(
            "rg_monitoring",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-{self.stack_name}-monitoring",
        )
        rg_storage = resources.ResourceGroup(
            "rg_storage",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-{self.stack_name}-storage",
        )
        rg_users = resources.ResourceGroup(
            "rg_users",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-{self.stack_name}-users",
        )

        # Deploy SHM networking
        networking = SHMNetworkingComponent(
            self.stack_name,
            SHMNetworkingProps(
                fqdn=self.cfg.shm.fqdn,
                public_ip_range_admins=self.cfg.shm.admin_ip_addresses,
                resource_group_name=rg_networking.name,
            ),
        )

        # Deploy SHM secrets
        secrets = SHMSecretsComponent(
            self.stack_name,
            SHMSecretsProps(
                admin_group_id=self.cfg.azure.admin_group_id,
                location=self.cfg.azure.location,
                resource_group_name=rg_storage.name,
                tenant_id=self.cfg.azure.tenant_id,
            ),
        )

        # Deploy SHM monitoring
        monitoring = SHMMonitoringComponent(
            self.stack_name,
            SHMMonitoringProps(
                location=self.cfg.azure.location,
                resource_group_name=rg_monitoring.name,
            ),
        )

        # Deploy firewall

        # Deploy update servers

        # Deploy domain controllers
        domain_controllers = SHMDomainControllersComponent(
            self.stack_name,
            SHMDomainControllersProps(
                automation_account_registration_key=monitoring.automation_account_primary_key,
                automation_account_registration_url=monitoring.automation_account_agentsvc_url,
                automation_account_name=monitoring.automation_account.name,
                automation_account_resource_group_name=monitoring.resource_group_name,
                domain_fqdn=self.cfg.shm.fqdn,
                domain_netbios_name=self.stack_name[4:].upper(),  # drop initial 'shm-'
                location=self.cfg.azure.location,
                password_domain_admin=self.secrets.require("password-domain-admin"),
                password_domain_azuread_connect=self.secrets.require(
                    "password-domain-azure-ad-connect"
                ),
                password_domain_computer_manager=self.secrets.require(
                    "password-domain-computer-manager"
                ),
                resource_group_name=rg_users.name,
                subnet_ip_range=networking.subnet_users_iprange,
                subnet_name="UsersSubnet",
                subscription_name=self.cfg.subscription_name,
                virtual_network_name=networking.virtual_network.name,
                virtual_network_resource_group_name=networking.resource_group_name,
            ),
        )
