"""Pulumi declarative program"""

import pulumi
from pulumi_azure_native import resources

from data_safe_haven.config import Context, SREConfig
from data_safe_haven.functions import replace_separators
from data_safe_haven.infrastructure.common import DockerHubCredentials

from .sre.application_gateway import (
    SREApplicationGatewayComponent,
    SREApplicationGatewayProps,
)
from .sre.apt_proxy_server import SREAptProxyServerComponent, SREAptProxyServerProps
from .sre.backup import SREBackupComponent, SREBackupProps
from .sre.clamav_mirror import SREClamAVMirrorComponent, SREClamAVMirrorProps
from .sre.data import SREDataComponent, SREDataProps
from .sre.dns_server import SREDnsServerComponent, SREDnsServerProps
from .sre.firewall import SREFirewallComponent, SREFirewallProps
from .sre.identity import SREIdentityComponent, SREIdentityProps
from .sre.monitoring import SREMonitoringComponent, SREMonitoringProps
from .sre.networking import SRENetworkingComponent, SRENetworkingProps
from .sre.remote_desktop import SRERemoteDesktopComponent, SRERemoteDesktopProps
from .sre.user_services import SREUserServicesComponent, SREUserServicesProps
from .sre.workspaces import SREWorkspacesComponent, SREWorkspacesProps


class DeclarativeSRE:
    """Deploy with Pulumi"""

    def __init__(
        self,
        context: Context,
        config: SREConfig,
        graph_api_token: str,
    ) -> None:
        self.context = context
        self.config = config
        self.graph_api_token = graph_api_token
        self.stack_name = replace_separators(
            f"shm-{context.name}-sre-{config.name}", "-"
        )
        self.tags = {
            "deployed with": "Pulumi",
            "sre_name": f"SRE {config.name}",
        } | context.tags

    def __call__(self) -> None:
        # Load pulumi configuration options
        self.pulumi_opts = pulumi.Config()
        shm_admin_group_id = self.pulumi_opts.require("shm-admin-group-id")
        shm_entra_tenant_id = self.pulumi_opts.require("shm-entra-tenant-id")
        shm_fqdn = self.pulumi_opts.require("shm-fqdn")

        # Construct DockerHubCredentials
        dockerhub_credentials = DockerHubCredentials(
            access_token=self.config.dockerhub.access_token,
            server="index.docker.io",
            username=self.config.dockerhub.username,
        )

        # Construct LDAP paths
        ldap_root_dn = f"DC={shm_fqdn.replace('.', ',DC=')}"
        ldap_group_search_base = f"OU=groups,{ldap_root_dn}"
        ldap_user_search_base = f"OU=users,{ldap_root_dn}"
        ldap_group_name_prefix = f"Data Safe Haven SRE {self.config.name}"
        ldap_group_names = {
            "admin_group_name": f"{ldap_group_name_prefix} Administrators",
            "privileged_user_group_name": f"{ldap_group_name_prefix} Privileged Users",
            "user_group_name": f"{ldap_group_name_prefix} Users",
        }
        ldap_username_attribute = "uid"
        # LDAP filter syntax: https://ldap.com/ldap-filters/
        # LDAP filter for users of this SRE
        ldap_user_filter = "".join(
            [
                "(&",
                # Users are a posixAccount and
                "(objectClass=posixAccount)",
                # belong to any of these groups
                "(|",
                *(
                    f"(memberOf=CN={group_name},{ldap_group_search_base})"
                    for group_name in ldap_group_names.values()
                ),
                ")",
                ")",
            ]
        )
        # LDAP filter for groups in this SRE
        ldap_group_filter = "".join(
            [
                "(&",
                # Groups are a posixGroup
                "(objectClass=posixGroup)",
                "(|",
                # which is either one of the LDAP groups
                *(f"(CN={group_name})" for group_name in ldap_group_names.values()),
                # or is the primary user group for a member of one of those groups
                *(
                    f"(memberOf=CN=Primary user groups for {group_name},{ldap_group_search_base})"
                    for group_name in ldap_group_names.values()
                ),
                ")",
                ")",
            ]
        )

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            "sre_resource_group",
            location=self.config.azure.location,
            resource_group_name=f"{self.stack_name}-rg",
            tags=self.tags,
        )

        # Deploy SRE DNS server
        dns = SREDnsServerComponent(
            "sre_dns_server",
            self.stack_name,
            SREDnsServerProps(
                dockerhub_credentials=dockerhub_credentials,
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                shm_fqdn=shm_fqdn,
            ),
            tags=self.tags,
        )

        # Deploy networking
        networking = SRENetworkingComponent(
            "sre_networking",
            self.stack_name,
            SRENetworkingProps(
                dns_private_zones=dns.private_zones,
                dns_server_ip=dns.ip_address,
                dns_virtual_network=dns.virtual_network,
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                shm_fqdn=shm_fqdn,
                shm_resource_group_name=self.context.resource_group_name,
                shm_zone_name=shm_fqdn,
                sre_name=self.config.name,
                user_public_ip_ranges=self.config.sre.research_user_ip_addresses,
            ),
            tags=self.tags,
        )

        # Deploy SRE firewall
        SREFirewallComponent(
            "sre_firewall",
            self.stack_name,
            SREFirewallProps(
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                route_table_name=networking.route_table_name,
                subnet_apt_proxy_server=networking.subnet_apt_proxy_server,
                subnet_clamav_mirror=networking.subnet_clamav_mirror,
                subnet_firewall=networking.subnet_firewall,
                subnet_firewall_management=networking.subnet_firewall_management,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
                subnet_identity_containers=networking.subnet_identity_containers,
                subnet_user_services_software_repositories=networking.subnet_user_services_software_repositories,
                subnet_workspaces=networking.subnet_workspaces,
            ),
            tags=self.tags,
        )

        # Deploy data storage
        data = SREDataComponent(
            "sre_data",
            self.stack_name,
            SREDataProps(
                admin_email_address=self.config.sre.admin_email_address,
                admin_group_id=shm_admin_group_id,
                admin_ip_addresses=self.config.sre.admin_ip_addresses,
                data_provider_ip_addresses=self.config.sre.data_provider_ip_addresses,
                dns_private_zones=dns.private_zones,
                dns_record=networking.shm_ns_record,
                dns_server_admin_password=dns.password_admin,
                location=self.config.azure.location,
                resource_group=resource_group,
                sre_fqdn=networking.sre_fqdn,
                storage_quota_gb_home=self.config.sre.storage_quota_gb.home,
                storage_quota_gb_shared=self.config.sre.storage_quota_gb.shared,
                subnet_data_configuration=networking.subnet_data_configuration,
                subnet_data_desired_state=networking.subnet_data_desired_state,
                subnet_data_private=networking.subnet_data_private,
                subscription_id=self.config.azure.subscription_id,
                subscription_name=self.context.subscription_name,
                tenant_id=self.config.azure.tenant_id,
            ),
            tags=self.tags,
        )

        # Deploy the apt proxy server
        apt_proxy_server = SREAptProxyServerComponent(
            "sre_apt_proxy_server",
            self.stack_name,
            SREAptProxyServerProps(
                containers_subnet=networking.subnet_apt_proxy_server,
                dns_server_ip=dns.ip_address,
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                sre_fqdn=networking.sre_fqdn,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
            ),
            tags=self.tags,
        )

        # Deploy the ClamAV mirror server
        clamav_mirror = SREClamAVMirrorComponent(
            "sre_clamav_mirror",
            self.stack_name,
            SREClamAVMirrorProps(
                dns_server_ip=dns.ip_address,
                dockerhub_credentials=dockerhub_credentials,
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                sre_fqdn=networking.sre_fqdn,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
                subnet=networking.subnet_clamav_mirror,
            ),
            tags=self.tags,
        )

        # Deploy identity server
        identity = SREIdentityComponent(
            "sre_identity",
            self.stack_name,
            SREIdentityProps(
                dns_server_ip=dns.ip_address,
                dockerhub_credentials=dockerhub_credentials,
                entra_application_name=f"sre-{self.config.name}-apricot",
                entra_auth_token=self.graph_api_token,
                entra_tenant_id=shm_entra_tenant_id,
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                shm_fqdn=shm_fqdn,
                sre_fqdn=networking.sre_fqdn,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
                subnet_containers=networking.subnet_identity_containers,
            ),
            tags=self.tags,
        )

        # Deploy frontend application gateway
        SREApplicationGatewayComponent(
            "sre_application_gateway",
            self.stack_name,
            SREApplicationGatewayProps(
                key_vault_certificate_id=data.sre_fqdn_certificate_secret_id,
                key_vault_identity=data.managed_identity,
                location=self.config.azure.location,
                resource_group=resource_group,
                subnet_application_gateway=networking.subnet_application_gateway,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
                sre_fqdn=networking.sre_fqdn,
            ),
            tags=self.tags,
        )

        # Deploy containerised remote desktop gateway
        remote_desktop = SRERemoteDesktopComponent(
            "sre_remote_desktop",
            self.stack_name,
            SRERemoteDesktopProps(
                allow_copy=self.config.sre.remote_desktop.allow_copy,
                allow_paste=self.config.sre.remote_desktop.allow_paste,
                database_password=data.password_user_database_admin,
                dns_server_ip=dns.ip_address,
                dockerhub_credentials=dockerhub_credentials,
                entra_application_fqdn=networking.sre_fqdn,
                entra_application_name=f"sre-{self.config.name}-guacamole",
                entra_auth_token=self.graph_api_token,
                entra_tenant_id=shm_entra_tenant_id,
                ldap_group_filter=ldap_group_filter,
                ldap_group_search_base=ldap_group_search_base,
                ldap_server_hostname=identity.hostname,
                ldap_server_port=identity.server_port,
                ldap_user_filter=ldap_user_filter,
                ldap_user_search_base=ldap_user_search_base,
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
                subnet_guacamole_containers_support=networking.subnet_guacamole_containers_support,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
            ),
            tags=self.tags,
        )

        # Deploy containerised user services
        user_services = SREUserServicesComponent(
            "sre_user_services",
            self.stack_name,
            SREUserServicesProps(
                database_service_admin_password=data.password_database_service_admin,
                databases=self.config.sre.databases,
                dns_server_ip=dns.ip_address,
                dockerhub_credentials=dockerhub_credentials,
                gitea_database_password=data.password_gitea_database_admin,
                hedgedoc_database_password=data.password_hedgedoc_database_admin,
                ldap_server_hostname=identity.hostname,
                ldap_server_port=identity.server_port,
                ldap_user_filter=ldap_user_filter,
                ldap_username_attribute=ldap_username_attribute,
                ldap_user_search_base=ldap_user_search_base,
                location=self.config.azure.location,
                nexus_admin_password=data.password_nexus_admin,
                resource_group_name=resource_group.name,
                software_packages=self.config.sre.software_packages,
                sre_fqdn=networking.sre_fqdn,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
                subnet_containers=networking.subnet_user_services_containers,
                subnet_containers_support=networking.subnet_user_services_containers_support,
                subnet_databases=networking.subnet_user_services_databases,
                subnet_software_repositories=networking.subnet_user_services_software_repositories,
            ),
            tags=self.tags,
        )

        # Deploy monitoring
        monitoring = SREMonitoringComponent(
            "sre_monitoring",
            self.stack_name,
            SREMonitoringProps(
                dns_private_zones=dns.private_zones,
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                subnet=networking.subnet_monitoring,
                timezone=self.config.sre.timezone,
            ),
            tags=self.tags,
        )

        # Deploy workspaces
        workspaces = SREWorkspacesComponent(
            "sre_workspaces",
            self.stack_name,
            SREWorkspacesProps(
                admin_password=data.password_workspace_admin,
                apt_proxy_server_hostname=apt_proxy_server.hostname,
                clamav_mirror_hostname=clamav_mirror.hostname,
                data_collection_rule_id=monitoring.data_collection_rule_vms.id,
                data_collection_endpoint_id=monitoring.data_collection_endpoint.id,
                database_service_admin_password=data.password_database_service_admin,
                gitea_hostname=user_services.gitea_server.hostname,
                hedgedoc_hostname=user_services.hedgedoc_server.hostname,
                ldap_group_filter=ldap_group_filter,
                ldap_group_search_base=ldap_group_search_base,
                ldap_server_hostname=identity.hostname,
                ldap_server_port=identity.server_port,
                ldap_user_filter=ldap_user_filter,
                ldap_user_search_base=ldap_user_search_base,
                location=self.config.azure.location,
                maintenance_configuration_id=monitoring.maintenance_configuration.id,
                resource_group_name=resource_group.name,
                software_repository_hostname=user_services.software_repositories.hostname,
                sre_name=self.config.name,
                storage_account_data_desired_state_name=data.storage_account_data_desired_state_name,
                storage_account_data_private_user_name=data.storage_account_data_private_user_name,
                storage_account_data_private_sensitive_name=data.storage_account_data_private_sensitive_name,
                subnet_workspaces=networking.subnet_workspaces,
                subscription_name=self.context.subscription_name,
                virtual_network=networking.virtual_network,
                vm_details=list(enumerate(self.config.sre.workspace_skus)),
            ),
            tags=self.tags,
        )

        # Deploy backup service
        SREBackupComponent(
            "sre_backup",
            self.stack_name,
            SREBackupProps(
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                storage_account_data_private_sensitive_id=data.storage_account_data_private_sensitive_id,
                storage_account_data_private_sensitive_name=data.storage_account_data_private_sensitive_name,
            ),
            tags=self.tags,
        )

        # Export values for later use
        pulumi.export("data", data.exports)
        pulumi.export("ldap", ldap_group_names)
        pulumi.export("remote_desktop", remote_desktop.exports)
        pulumi.export("workspaces", workspaces.exports)
