"""Deploy Data Safe Haven Management environment with Pulumi"""
# Third party imports
import pulumi
from pulumi_azure_native import resources

# Local imports
from .components.shm_networking import SHMNetworkingComponent, SHMNetworkingProps
from .components.shm_secrets import SHMSecretsComponent, SHMSecretsProps


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
        rg_storage = resources.ResourceGroup(
            "rg_storage",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-shm-{self.cfg.shm.name}-storage",
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
