"""Deploy Data Safe Haven Management environment with Pulumi"""

import pulumi

from data_safe_haven.config import Config
from data_safe_haven.context import Context

from .shm.firewall import SHMFirewallComponent, SHMFirewallProps
from .shm.monitoring import SHMMonitoringComponent, SHMMonitoringProps
from .shm.networking import SHMNetworkingComponent, SHMNetworkingProps


class DeclarativeSHM:
    """Deploy Data Safe Haven Management environment with Pulumi"""

    def __init__(self, context: Context, config: Config, shm_name: str) -> None:
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

        # Deploy firewall and routing
        firewall = SHMFirewallComponent(
            "shm_firewall",
            self.stack_name,
            SHMFirewallProps(
                dns_zone=networking.dns_zone,
                location=self.context.location,
                resource_group_name=networking.resource_group_name,
                route_table_name=networking.route_table.name,
                subnet_firewall=networking.subnet_firewall,
            ),
            tags=self.tags,
        )

        # Deploy automated monitoring
        monitoring = SHMMonitoringComponent(
            "shm_monitoring",
            self.stack_name,
            SHMMonitoringProps(
                dns_resource_group_name=networking.resource_group_name,
                location=self.context.location,
                private_dns_zone_base_id=networking.private_dns_zone_base_id,
                subnet_monitoring=networking.subnet_monitoring,
                timezone=self.cfg.shm.timezone,
            ),
            tags=self.tags,
        )

        # Export values for later use
        pulumi.export("firewall", firewall.exports)
        pulumi.export("monitoring", monitoring.exports)
        pulumi.export("networking", networking.exports)
