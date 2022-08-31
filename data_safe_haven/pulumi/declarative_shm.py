"""Deploy Data Safe Haven Management environment with Pulumi"""
# Third party imports
import pulumi
from pulumi_azure_native import resources

# Local imports
from .components.shm_networking import SHMNetworkingComponent, SHMNetworkingProps


class DeclarativeSHM:
    """Deploy Data Safe Haven Management environment with Pulumi"""

    def __init__(self, config):
        self.cfg = config

    def run(self):
        # Load pulumi configuration secrets
        self.secrets = pulumi.Config()

        # Define resource groups
        rg_users = resources.ResourceGroup(
            "rg_users",
            resource_group_name=f"rg-shm-{self.cfg.shm.name}-users",
        )
        rg_networking = resources.ResourceGroup(
            "rg_networking",
            resource_group_name=f"rg-shm-{self.cfg.shm.name}-networking",
        )

        # Deploy SHM networking
        networking = SHMNetworkingComponent(
            self.cfg.shm.name,
            SHMNetworkingProps(
                fqdn=self.cfg.shm.fqdn,
                resource_group_name=rg_networking.name,
            ),
        )
