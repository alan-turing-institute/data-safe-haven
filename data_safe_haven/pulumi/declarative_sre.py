"""Pulumi declarative program"""
# Standard library imports
import pathlib

# Third party imports
import pulumi

# Local imports
from data_safe_haven.config import Config
from .components.sre_application_gateway import (
    SREApplicationGatewayComponent,
    SREApplicationGatewayProps,
)
from .components.sre_monitoring import SREMonitoringComponent, SREMonitoringProps
from .components.sre_networking import SRENetworkingComponent, SRENetworkingProps
from .components.sre_remote_desktop import (
    SRERemoteDesktopComponent,
    SRERemoteDesktopProps,
)
from .components.sre_research_desktop import (
    SREResearchDesktopComponent,
    SREResearchDesktopProps,
)
from .components.sre_state import SREStateComponent, SREStateProps


class DeclarativeSRE:
    """Deploy with Pulumi"""

    def __init__(self, config: Config, shm_name: str, sre_name: str) -> None:
        self.cfg = config
        self.shm_name = shm_name
        self.sre_name = sre_name
        self.stack_name = f"shm-{shm_name}-sre-{sre_name}"

    def work_dir(self, base_path: pathlib.Path) -> pathlib.Path:
        return base_path / f"shm-{self.shm_name}" / f"sre-{self.sre_name}"

    def run(self) -> None:
        # Load pulumi configuration options
        self.pulumi_opts = pulumi.Config()

        # Deploy networking
        networking = SRENetworkingComponent(
            "sre_networking",
            self.stack_name,
            self.sre_name,
            SRENetworkingProps(
                location=self.cfg.azure.location,
                shm_fqdn=self.cfg.shm.fqdn,
                shm_networking_resource_group_name=self.pulumi_opts.require(
                    "shm-networking-resource_group_name"
                ),
                shm_subnet_identity_servers_prefix=self.pulumi_opts.require(
                    "shm-networking-subnet_identity_servers_prefix",
                ),
                shm_subnet_monitoring_prefix=self.pulumi_opts.require(
                    "shm-networking-subnet_subnet_monitoring_prefix",
                ),
                shm_subnet_update_servers_prefix=self.pulumi_opts.require(
                    "shm-networking-subnet_update_servers_prefix",
                ),
                shm_zone_name=self.cfg.shm.fqdn,
                sre_index=self.cfg.sre[self.sre_name].index,
                shm_virtual_network_name=self.pulumi_opts.require(
                    "shm-networking-virtual_network_name"
                ),
            ),
        )

        # Deploy automated monitoring
        monitoring = SREMonitoringComponent(
            "sre_monitoring",
            self.stack_name,
            self.shm_name,
            SREMonitoringProps(
                automation_account_name=self.pulumi_opts.require(
                    "shm-monitoring-automation_account_name"
                ),
                location=self.cfg.azure.location,
                subscription_resource_id=networking.resource_group.id.apply(
                    lambda id_: id_.split("/resourceGroups/")[0]
                ),
                resource_group_name=self.pulumi_opts.require(
                    "shm-monitoring-resource_group_name"
                ),
                sre_index=self.cfg.sre[self.sre_name].index,
                timezone=self.cfg.shm.timezone,
            ),
        )

        # Deploy state storage
        state = SREStateComponent(
            "sre_state",
            self.stack_name,
            self.sre_name,
            SREStateProps(
                admin_email_address=self.cfg.shm.admin_email_address,
                admin_group_id=self.cfg.azure.admin_group_id,
                dns_record=networking.shm_ns_record,
                location=self.cfg.azure.location,
                networking_resource_group=networking.resource_group,
                pulumi_opts=self.pulumi_opts,
                sre_fqdn=networking.sre_fqdn,
                subscription_name=self.cfg.subscription_name,
                tenant_id=self.cfg.azure.tenant_id,
            ),
        )

        # Deploy frontend application gateway
        application_gateway = SREApplicationGatewayComponent(
            "sre_application_gateway",
            self.stack_name,
            self.sre_name,
            SREApplicationGatewayProps(
                key_vault_certificate_id=state.certificate_secret_id,
                key_vault_identity=state.managed_identity,
                resource_group=networking.resource_group,
                subnet_application_gateway=networking.subnet_application_gateway,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
                sre_fqdn=networking.sre_fqdn,
            ),
        )

        # Deploy containerised remote desktop gateway
        remote_desktop = SRERemoteDesktopComponent(
            "sre_remote_desktop",
            self.stack_name,
            self.sre_name,
            SRERemoteDesktopProps(
                aad_application_name=f"sre-{self.sre_name}-azuread-guacamole",
                aad_application_fqdn=networking.sre_fqdn,
                aad_auth_token=self.pulumi_opts.require("token-azuread-graphapi"),
                aad_tenant_id=self.cfg.shm.aad_tenant_id,
                allow_copy=self.cfg.sre[self.sre_name].remote_desktop.allow_copy,
                allow_paste=self.cfg.sre[self.sre_name].remote_desktop.allow_paste,
                database_password=state.password_user_database_admin,
                location=self.cfg.azure.location,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
                subnet_guacamole_database=networking.subnet_guacamole_database,
                storage_account_name=state.account_name,
                storage_account_resource_group=state.resource_group_name,
                virtual_network_resource_group=networking.resource_group,
                virtual_network=networking.virtual_network,
            ),
        )

        # Deploy secure research desktops
        research_desktops = SREResearchDesktopComponent(
            "sre_secure_research_desktop",
            self.stack_name,
            self.sre_name,
            SREResearchDesktopProps(
                admin_password=state.password_secure_research_desktop_admin,
                domain_sid=self.pulumi_opts.require(
                    "shm-domain_controllers-domain_sid"
                ),
                ldap_root_dn=self.pulumi_opts.require(
                    "shm-domain_controllers-ldap_root_dn"
                ),
                ldap_search_password=self.pulumi_opts.require(
                    "password-domain-ldap-searcher"
                ),
                ldap_server_ip=self.pulumi_opts.require(
                    "shm-domain_controllers-ldap_server_ip"
                ),
                linux_update_server_ip=self.pulumi_opts.require(
                    "shm-update_servers-ip_address_linux"
                ),
                location=self.cfg.azure.location,
                log_analytics_workspace_id=self.pulumi_opts.require(
                    "shm-monitoring-log_analytics_workspace_id"
                ),
                log_analytics_workspace_key=self.pulumi_opts.require(
                    "shm-monitoring-log_analytics_workspace_key"
                ),
                security_group_name=f"Data Safe Haven Users SRE {self.sre_name}",
                subnet_research_desktops=networking.subnet_research_desktops,
                virtual_network_resource_group=networking.resource_group,
                virtual_network=networking.virtual_network,
                vm_details=[
                    (idx, str(name), str(details["sku"]))
                    for idx, (name, details) in enumerate(
                        self.cfg.sre[self.sre_name].research_desktops.items()
                    )
                ],
            ),
        )

        # Export values for later use
        pulumi.export("remote_desktop", remote_desktop.exports)
        pulumi.export("research_desktops", research_desktops.exports)
