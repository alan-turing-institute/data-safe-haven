"""Deploy Data Safe Haven Management environment with Pulumi"""
# Third party imports
import pulumi
from pulumi_azure_native import network, resources

class DeclarativeSHM:
    """Deploy Data Safe Haven Management environment with Pulumi"""

    def __init__(self, config):
        self.cfg = config

    def run(self):
        # Load pulumi configuration secrets
        self.secrets = pulumi.Config()

        # Define resource groups
        rg_identity = resources.ResourceGroup(
            "rg_identity",
            resource_group_name=f"rg-shm-{self.cfg.shm.name}-identity",
        )
        rg_networking = resources.ResourceGroup(
            "rg_networking",
            resource_group_name=f"rg-shm-{self.cfg.shm.name}-networking",
        )


        # Define SHM DNS
        dns_zone = network.Zone(
            "dns_zone",
            location="Global",
            resource_group_name=rg_networking.name,
            zone_name=self.cfg.shm.fqdn,
            zone_type="Public"
        )
