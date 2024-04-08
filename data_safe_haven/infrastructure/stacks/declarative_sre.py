"""Pulumi declarative program"""

import pulumi

from data_safe_haven.config import Config
from data_safe_haven.infrastructure.common import get_subscription_id_from_rg

from .sre.application_gateway import (
    SREApplicationGatewayComponent,
    SREApplicationGatewayProps,
)
from .sre.backup import (
    SREBackupComponent,
    SREBackupProps,
)
from .sre.data import (
    SREDataComponent,
    SREDataProps,
)
from .sre.dns_server import (
    SREDnsServerComponent,
    SREDnsServerProps,
)
from .sre.identity import (
    SREIdentityComponent,
    SREIdentityProps,
)
from .sre.monitoring import (
    SREMonitoringComponent,
    SREMonitoringProps,
)
from .sre.networking import (
    SRENetworkingComponent,
    SRENetworkingProps,
)
from .sre.remote_desktop import (
    SRERemoteDesktopComponent,
    SRERemoteDesktopProps,
)
from .sre.user_services import (
    SREUserServicesComponent,
    SREUserServicesProps,
)
from .sre.workspaces import (
    SREWorkspacesComponent,
    SREWorkspacesProps,
)


class DeclarativeSRE:
    """Deploy with Pulumi"""

    def __init__(
        self, config: Config, shm_name: str, sre_name: str, graph_api_token: str
    ) -> None:
        self.cfg = config
        self.graph_api_token = graph_api_token
        self.shm_name = shm_name
        self.sre_name = sre_name
        self.short_name = f"sre-{sre_name}"
        self.stack_name = f"shm-{shm_name}-{self.short_name}"

    def run(self) -> None:
        # Load pulumi configuration options
        self.pulumi_opts = pulumi.Config()

        # Construct LDAP paths
        ldap_root_dn = self.pulumi_opts.require("shm-domain_controllers-ldap_root_dn")
        ldap_group_search_base = f"OU=groups,{ldap_root_dn}"
        ldap_user_search_base = f"OU=users,{ldap_root_dn}"
        ldap_group_name_prefix = f"Data Safe Haven SRE {self.sre_name}"
        ldap_admin_group_name = f"{ldap_group_name_prefix} Administrators"
        ldap_privileged_user_group_name = f"{ldap_group_name_prefix} Privileged Users"
        ldap_username_attribute = "uid"
        ldap_user_group_name = f"{ldap_group_name_prefix} Users"
        # Users are a posixAccount belonging to any of these groups
        ldap_user_filter = "".join(
            [
                "(&",
                "(objectClass=posixAccount)",
                "(|",
                f"(memberOf=CN={ldap_admin_group_name},{ldap_group_search_base})"
                f"(memberOf=CN={ldap_privileged_user_group_name},{ldap_group_search_base})"
                f"(memberOf=CN={ldap_user_group_name},{ldap_group_search_base})"
                ")",
                ")",
            ]
        )
        # Groups are a posixGroup which is either a known, named group or belonging to any of these groups
        ldap_group_filter = "".join(
            [
                "(&",
                "(objectClass=posixGroup)",
                "(|",
                f"(CN={ldap_admin_group_name})",
                f"(CN={ldap_privileged_user_group_name})",
                f"(CN={ldap_user_group_name})",
                f"(memberOf=CN=Primary user groups for {ldap_admin_group_name},{ldap_group_search_base})",
                f"(memberOf=CN=Primary user groups for {ldap_privileged_user_group_name},{ldap_group_search_base})",
                f"(memberOf=CN=Primary user groups for {ldap_user_group_name},{ldap_group_search_base})",
                ")",
                ")",
            ]
        )

        # Deploy SRE DNS server
        dns = SREDnsServerComponent(
            "sre_dns_server",
            self.stack_name,
            SREDnsServerProps(
                location=self.cfg.azure.location,
                shm_fqdn=self.cfg.shm.fqdn,
                shm_networking_resource_group_name=self.pulumi_opts.require(
                    "shm-networking-resource_group_name"
                ),
                sre_index=self.cfg.sre(self.sre_name).index,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy networking
        networking = SRENetworkingComponent(
            "sre_networking",
            self.stack_name,
            SRENetworkingProps(
                dns_resource_group_name=dns.resource_group.name,
                dns_server_ip=dns.ip_address,
                dns_virtual_network=dns.virtual_network,
                firewall_ip_address=self.pulumi_opts.require(
                    "shm-firewall-private-ip-address"
                ),
                location=self.cfg.azure.location,
                shm_fqdn=self.cfg.shm.fqdn,
                shm_networking_resource_group_name=self.pulumi_opts.require(
                    "shm-networking-resource_group_name"
                ),
                shm_subnet_monitoring_prefix=self.pulumi_opts.require(
                    "shm-networking-subnet_subnet_monitoring_prefix",
                ),
                shm_subnet_update_servers_prefix=self.pulumi_opts.require(
                    "shm-networking-subnet_update_servers_prefix",
                ),
                shm_virtual_network_name=self.pulumi_opts.require(
                    "shm-networking-virtual_network_name"
                ),
                shm_zone_name=self.cfg.shm.fqdn,
                sre_index=self.cfg.sre(self.sre_name).index,
                sre_name=self.sre_name,
                user_public_ip_ranges=self.cfg.sre(
                    self.sre_name
                ).research_user_ip_addresses,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy automated monitoring
        SREMonitoringComponent(
            "sre_monitoring",
            self.stack_name,
            SREMonitoringProps(
                automation_account_name=self.pulumi_opts.require(
                    "shm-monitoring-automation_account_name"
                ),
                location=self.cfg.azure.location,
                subscription_resource_id=get_subscription_id_from_rg(
                    dns.resource_group
                ),
                resource_group_name=self.pulumi_opts.require(
                    "shm-monitoring-resource_group_name"
                ),
                sre_index=self.cfg.sre(self.sre_name).index,
                timezone=self.cfg.shm.timezone,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy data storage
        data = SREDataComponent(
            "sre_data",
            self.stack_name,
            SREDataProps(
                admin_email_address=self.cfg.shm.admin_email_address,
                admin_group_id=self.cfg.azure.admin_group_id,
                admin_ip_addresses=self.cfg.shm.admin_ip_addresses,
                data_provider_ip_addresses=self.cfg.sre(
                    self.sre_name
                ).data_provider_ip_addresses,
                dns_record=networking.shm_ns_record,
                dns_server_admin_password=dns.password_admin,
                location=self.cfg.azure.location,
                networking_resource_group=networking.resource_group,
                pulumi_opts=self.pulumi_opts,
                sre_fqdn=networking.sre_fqdn,
                subnet_data_configuration=networking.subnet_data_configuration,
                subnet_data_private=networking.subnet_data_private,
                subscription_id=self.cfg.azure.subscription_id,
                subscription_name=self.cfg.context.subscription_name,
                tenant_id=self.cfg.azure.tenant_id,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy identity server
        identity = SREIdentityComponent(
            "sre_identity",
            self.stack_name,
            SREIdentityProps(
                aad_application_name=f"sre-{self.sre_name}-apricot",
                aad_auth_token=self.graph_api_token,
                aad_tenant_id=self.cfg.shm.aad_tenant_id,
                location=self.cfg.azure.location,
                shm_fqdn=self.cfg.shm.fqdn,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
                storage_account_resource_group_name=data.resource_group_name,
                subnet_containers=networking.subnet_identity_containers,
            ),
        )

        # Deploy frontend application gateway
        SREApplicationGatewayComponent(
            "sre_application_gateway",
            self.stack_name,
            SREApplicationGatewayProps(
                key_vault_certificate_id=data.sre_fqdn_certificate_secret_id,
                key_vault_identity=data.managed_identity,
                resource_group=networking.resource_group,
                subnet_application_gateway=networking.subnet_application_gateway,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
                sre_fqdn=networking.sre_fqdn,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy containerised remote desktop gateway
        remote_desktop = SRERemoteDesktopComponent(
            "sre_remote_desktop",
            self.stack_name,
            SRERemoteDesktopProps(
                aad_application_fqdn=networking.sre_fqdn,
                aad_application_name=f"sre-{self.sre_name}-guacamole",
                aad_auth_token=self.graph_api_token,
                aad_tenant_id=self.cfg.shm.aad_tenant_id,
                allow_copy=self.cfg.sre(self.sre_name).remote_desktop.allow_copy,
                allow_paste=self.cfg.sre(self.sre_name).remote_desktop.allow_paste,
                database_password=data.password_user_database_admin,
                dns_server_ip=dns.ip_address,
                ldap_group_filter=ldap_group_filter,
                ldap_group_search_base=ldap_group_search_base,
                ldap_server_ip=identity.ip_address,
                ldap_server_port=identity.server_port,
                ldap_user_filter=ldap_user_filter,
                ldap_user_search_base=ldap_user_search_base,
                location=self.cfg.azure.location,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
                storage_account_resource_group_name=data.resource_group_name,
                subnet_guacamole_containers_support=networking.subnet_guacamole_containers_support,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy workspaces
        workspaces = SREWorkspacesComponent(
            "sre_workspaces",
            self.stack_name,
            SREWorkspacesProps(
                admin_password=data.password_workspace_admin,
                ldap_group_filter=ldap_group_filter,
                ldap_group_search_base=ldap_group_search_base,
                ldap_server_ip=identity.ip_address,
                ldap_server_port=identity.server_port,
                ldap_user_filter=ldap_user_filter,
                ldap_user_search_base=ldap_user_search_base,
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
                sre_fqdn=networking.sre_fqdn,
                sre_name=self.sre_name,
                storage_account_data_private_user_name=data.storage_account_data_private_user_name,
                storage_account_data_private_sensitive_name=data.storage_account_data_private_sensitive_name,
                subnet_workspaces=networking.subnet_workspaces,
                subscription_name=self.cfg.context.subscription_name,
                virtual_network_resource_group=networking.resource_group,
                virtual_network=networking.virtual_network,
                vm_details=list(enumerate(self.cfg.sre(self.sre_name).workspace_skus)),
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy containerised user services
        SREUserServicesComponent(
            "sre_user_services",
            self.stack_name,
            SREUserServicesProps(
                database_service_admin_password=data.password_database_service_admin,
                databases=self.cfg.sre(self.sre_name).databases,
                dns_resource_group_name=dns.resource_group.name,
                dns_server_ip=dns.ip_address,
                domain_netbios_name=self.pulumi_opts.require(
                    "shm-domain_controllers-netbios_name"
                ),
                gitea_database_password=data.password_gitea_database_admin,
                hedgedoc_database_password=data.password_hedgedoc_database_admin,
                ldap_server_ip=identity.ip_address,
                ldap_server_port=identity.server_port,
                ldap_user_filter=ldap_user_filter,
                ldap_username_attribute=ldap_username_attribute,
                ldap_user_search_base=ldap_user_search_base,
                location=self.cfg.azure.location,
                networking_resource_group_name=networking.resource_group.name,
                nexus_admin_password=data.password_nexus_admin,
                software_packages=self.cfg.sre(self.sre_name).software_packages,
                sre_fqdn=networking.sre_fqdn,
                sre_private_dns_zone_id=networking.sre_private_dns_zone_id,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
                storage_account_resource_group_name=data.resource_group_name,
                subnet_containers=networking.subnet_user_services_containers,
                subnet_containers_support=networking.subnet_user_services_containers_support,
                subnet_databases=networking.subnet_user_services_databases,
                subnet_software_repositories=networking.subnet_user_services_software_repositories,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Deploy backup service
        SREBackupComponent(
            "sre_user_services",
            self.stack_name,
            SREBackupProps(
                location=self.cfg.azure.location,
                storage_account_data_private_sensitive_id=data.storage_account_data_private_sensitive_id,
                storage_account_data_private_sensitive_name=data.storage_account_data_private_sensitive_name,
            ),
            tags=self.cfg.tags.model_dump(),
        )

        # Export values for later use
        pulumi.export("data", data.exports)
        pulumi.export(
            "ldap",
            {
                "admin_security_group_name": ldap_admin_group_name,
                "privileged_user_security_group_name": ldap_privileged_user_group_name,
                "user_security_group_name": ldap_user_group_name,
            },
        )
        pulumi.export("remote_desktop", remote_desktop.exports)
        pulumi.export("workspaces", workspaces.exports)
