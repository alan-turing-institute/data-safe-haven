"""Deploy Data Safe Haven Management environment with Pulumi"""

import pulumi

from data_safe_haven.config import Config

from .shm.data import SHMDataComponent, SHMDataProps
from .shm.firewall import SHMFirewallComponent, SHMFirewallProps
from .shm.monitoring import SHMMonitoringComponent, SHMMonitoringProps
from .shm.networking import SHMNetworkingComponent, SHMNetworkingProps
from .shm.update_servers import SHMUpdateServersComponent, SHMUpdateServersProps


class DeclarativeSHM:
    """Deploy Data Safe Haven Management environment with Pulumi"""

    def __init__(self, config: Config, shm_name: str) -> None:
        self.cfg = config
        self.shm_name = shm_name
        self.short_name = f"shm-{shm_name}"
        self.stack_name = self.short_name

    def run(self) -> None:
        # Load pulumi configuration options
        self.pulumi_opts = pulumi.Config()

        # Deploy networking
        networking = SHMNetworkingComponent(
            "shm_networking",
            self.stack_name,
            SHMNetworkingProps(
                admin_ip_addresses=self.cfg.shm.admin_ip_addresses,
                fqdn=self.cfg.shm.fqdn,
                location=self.cfg.azure.location,
                record_domain_verification=self.pulumi_opts.require(
                    "verification-azuread-custom-domain"
                ),
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy firewall and routing
        firewall = SHMFirewallComponent(
            "shm_firewall",
            self.stack_name,
            SHMFirewallProps(
                dns_zone=networking.dns_zone,
                location=self.cfg.azure.location,
                resource_group_name=networking.resource_group_name,
                route_table_name=networking.route_table.name,
                subnet_firewall=networking.subnet_firewall,
                subnet_identity_servers=networking.subnet_identity_servers,
                subnet_update_servers=networking.subnet_update_servers,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy data storage
        data = SHMDataComponent(
            "shm_data",
            self.stack_name,
            SHMDataProps(
                admin_group_id=self.cfg.azure.admin_group_id,
                admin_ip_addresses=self.cfg.shm.admin_ip_addresses,
                location=self.cfg.azure.location,
                tenant_id=self.cfg.azure.tenant_id,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy automated monitoring
        monitoring = SHMMonitoringComponent(
            "shm_monitoring",
            self.stack_name,
            SHMMonitoringProps(
                dns_resource_group_name=networking.resource_group_name,
                location=self.cfg.azure.location,
                private_dns_zone_base_id=networking.private_dns_zone_base_id,
                subnet_monitoring=networking.subnet_monitoring,
                timezone=self.cfg.shm.timezone,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy update servers
        update_servers = SHMUpdateServersComponent(
            "shm_update_servers",
            self.stack_name,
            SHMUpdateServersProps(
                admin_password=data.password_update_server_linux_admin,
                location=self.cfg.azure.location,
                log_analytics_workspace=monitoring.log_analytics_workspace,
                resource_group_name=monitoring.resource_group_name,
                subnet=networking.subnet_update_servers,
                virtual_network_name=networking.virtual_network.name,
                virtual_network_resource_group_name=networking.resource_group_name,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Export values for later use
        pulumi.export("firewall", firewall.exports)
        pulumi.export("monitoring", monitoring.exports)
        pulumi.export("networking", networking.exports)
        pulumi.export("update_servers", update_servers.exports)
