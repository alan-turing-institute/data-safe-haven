"""Deploy Data Safe Haven Management environment with Pulumi"""

import pulumi

from data_safe_haven.config import SHMConfig
from data_safe_haven.context import Context

from .shm.networking import SHMNetworkingComponent, SHMNetworkingProps


class DeclarativeSHM:
    """Deploy Data Safe Haven Management environment with Pulumi"""

    def __init__(self, context: Context, config: SHMConfig, shm_name: str) -> None:
        self.context = context
        self.cfg = config
        self.shm_name = shm_name
        self.short_name = f"shm-{shm_name}"
        self.stack_name = self.short_name
        self.tags = context.tags

    def __call__(self) -> None:
        # Load pulumi configuration options
        self.pulumi_opts = pulumi.Config()

        # Deploy networking
        networking = SHMNetworkingComponent(
            "shm_networking",
            self.stack_name,
            SHMNetworkingProps(
                admin_ip_addresses=self.cfg.shm.admin_ip_addresses,
                fqdn=self.cfg.shm.fqdn,
                location=self.context.location,
                record_domain_verification=self.pulumi_opts.require(
                    "verification-azuread-custom-domain"
                ),
            ),
            tags=self.tags,
        )

        # Export values for later use
        pulumi.export("networking", networking.exports)
