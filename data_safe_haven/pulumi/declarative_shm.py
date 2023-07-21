"""Deploy Data Safe Haven Management environment with Pulumi"""
# Third party imports
import pulumi

# Local imports
from data_safe_haven.config import Config
from .components.shm_bastion import SHMBastionComponent, SHMBastionProps
from .components.shm_data import SHMDataComponent, SHMDataProps
from .components.shm_domain_controllers import (
    SHMDomainControllersComponent,
    SHMDomainControllersProps,
)
from .components.shm_firewall import SHMFirewallComponent, SHMFirewallProps
from .components.shm_monitoring import SHMMonitoringComponent, SHMMonitoringProps
from .components.shm_networking import SHMNetworkingComponent, SHMNetworkingProps
from .components.shm_update_servers import (
    SHMUpdateServersComponent,
    SHMUpdateServersProps,
)


class DeclarativeSHM:
    """Deploy Data Safe Haven Management environment with Pulumi"""

    def __init__(self, config: Config, shm_name: str) -> None:
        self.cfg = config
        self.shm_name = shm_name
        self.stack_name = f"shm-{shm_name}"

    def run(self) -> None:
        # Load pulumi configuration options
        self.pulumi_opts = pulumi.Config()

        # Deploy networking
        networking = SHMNetworkingComponent(
            "shm_networking",
            self.stack_name,
            self.shm_name,
            SHMNetworkingProps(
                admin_ip_addresses=self.cfg.shm.admin_ip_addresses,
                fqdn=self.cfg.shm.fqdn,
                location=self.cfg.azure.location,
                record_domain_verification=self.pulumi_opts.require(
                    "verification-azuread-custom-domain"
                ),
            ),
        )

        # Deploy firewall and routing
        firewall = SHMFirewallComponent(
            "shm_firewall",
            self.stack_name,
            self.shm_name,
            SHMFirewallProps(
                domain_controller_private_ip=networking.domain_controller_private_ip,
                dns_zone=networking.dns_zone,
                location=self.cfg.azure.location,
                resource_group_name=networking.resource_group_name,
                route_table_name=networking.route_table.name,
                subnet_firewall=networking.subnet_firewall,
                subnet_identity_servers=networking.subnet_identity_servers,
                subnet_update_servers=networking.subnet_update_servers,
            ),
        )

        # Deploy firewall and routing
        bastion = SHMBastionComponent(
            "shm_bastion",
            self.stack_name,
            self.shm_name,
            SHMBastionProps(
                location=self.cfg.azure.location,
                resource_group_name=networking.resource_group_name,
                subnet=networking.subnet_bastion,
            ),
        )

        # Deploy data storage
        data = SHMDataComponent(
            "shm_data",
            self.stack_name,
            self.shm_name,
            SHMDataProps(
                admin_group_id=self.cfg.azure.admin_group_id,
                admin_ip_addresses=self.cfg.shm.admin_ip_addresses,
                location=self.cfg.azure.location,
                pulumi_opts=self.pulumi_opts,
                tenant_id=self.cfg.azure.tenant_id,
            ),
        )

        # Deploy automated monitoring
        monitoring = SHMMonitoringComponent(
            "shm_monitoring",
            self.stack_name,
            self.shm_name,
            SHMMonitoringProps(
                dns_resource_group_name=networking.resource_group_name,
                location=self.cfg.azure.location,
                private_dns_zone_base_id=networking.private_dns_zone_base_id,
                subnet_monitoring=networking.subnet_monitoring,
                timezone=self.cfg.shm.timezone,
            ),
        )

        # Deploy update servers
        update_servers = SHMUpdateServersComponent(
            "shm_update_servers",
            self.stack_name,
            self.shm_name,
            SHMUpdateServersProps(
                admin_password=data.password_update_server_linux_admin,
                location=self.cfg.azure.location,
                log_analytics_workspace_id=monitoring.log_analytics_workspace_id,
                log_analytics_workspace_key=monitoring.log_analytics_workspace_key,
                resource_group_name=monitoring.resource_group_name,
                subnet=networking.subnet_update_servers,
                virtual_network_name=networking.virtual_network.name,
                virtual_network_resource_group_name=networking.resource_group_name,
            ),
        )

        # Deploy domain controllers
        domain_controllers = SHMDomainControllersComponent(
            "shm_domain_controllers",
            self.stack_name,
            self.shm_name,
            SHMDomainControllersProps(
                automation_account_modules=monitoring.automation_account_modules,
                automation_account_name=monitoring.automation_account.name,
                automation_account_registration_key=monitoring.automation_account_primary_key,
                automation_account_registration_url=monitoring.automation_account_agentsvc_url,
                automation_account_resource_group_name=monitoring.resource_group_name,
                domain_fqdn=networking.dns_zone.name,
                domain_netbios_name=self.shm_name.upper(),
                location=self.cfg.azure.location,
                log_analytics_workspace_id=monitoring.log_analytics_workspace_id,
                log_analytics_workspace_key=monitoring.log_analytics_workspace_key,
                password_domain_admin=data.password_domain_admin,
                password_domain_azuread_connect=data.password_domain_azure_ad_connect,
                password_domain_computer_manager=data.password_domain_computer_manager,
                password_domain_searcher=data.password_domain_searcher,
                private_ip_address=networking.domain_controller_private_ip,
                subnet_identity_servers=networking.subnet_identity_servers,
                subscription_name=self.cfg.subscription_name,
                virtual_network_name=networking.virtual_network.name,
                virtual_network_resource_group_name=networking.resource_group_name,
            ),
        )

        # Export values for later use
        pulumi.export("domain_controllers", domain_controllers.exports)
        pulumi.export("fqdn_nameservers", networking.dns_zone.name_servers)
        pulumi.export("monitoring", monitoring.exports)
        pulumi.export("networking", networking.exports)
        pulumi.export("update_servers", update_servers.exports)
