"""Pulumi declarative program"""

import pulumi
from pulumi import Output, ResourceOptions
from pulumi_azure_native import resources

from data_safe_haven.config import Context, SREConfig
from data_safe_haven.functions import replace_separators
from data_safe_haven.infrastructure.common import (
    DockerHubCredentials,
    get_id_from_subnet,
)
from data_safe_haven.infrastructure.programs.sre.dns_sidecar import (
    DnsSidecarComponent,
    DnsSidecarProps,
    SupportsDnsSidecar,
)

from .sre.application_gateway import (
    SREApplicationGatewayComponent,
    SREApplicationGatewayProps,
)
from .sre.apt_proxy_server import SREAptProxyServerComponent, SREAptProxyServerProps
from .sre.clamav_mirror import SREClamAVMirrorComponent, SREClamAVMirrorProps
from .sre.data import SREDataComponent, SREDataProps
from .sre.desired_state import SREDesiredStateComponent, SREDesiredStateProps
from .sre.dns_server import SREDnsServerComponent, SREDnsServerProps
from .sre.entra import SREEntraComponent, SREEntraProps
from .sre.firewall import SREFirewallComponent, SREFirewallProps
from .sre.identity import SREIdentityComponent, SREIdentityProps
from .sre.monitoring import (
    SREMonitoringComponent,
    SREMonitoringNetworkingProps,
)
from .sre.monitoring_elements import (
    SREMonitoringElementsComponent,
    SREMonitoringElementsProps,
)
from .sre.networking import (
    SRENetworkingComponent,
    SRENetworkingProps,
)
from .sre.remote_desktop import SRERemoteDesktopComponent, SRERemoteDesktopProps
from .sre.user_services import SREUserServicesComponent, SREUserServicesProps
from .sre.workspaces import SREWorkspacesComponent, SREWorkspacesProps


class DeclarativeSRE:
    """Deploy with Pulumi"""

    def __init__(
        self,
        context: Context,
        config: SREConfig,
    ) -> None:
        self.context = context
        self.config = config
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
        shm_location = self.pulumi_opts.require("shm-location")
        shm_subscription_id = self.pulumi_opts.require("shm-subscription-id")
        sre_subscription_name = self.pulumi_opts.require("sre-subscription-name")

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

        # Deploy monitoring elements
        monitoring_elements = SREMonitoringElementsComponent(
            "sre_monitoring_elements",
            self.stack_name,
            SREMonitoringElementsProps(
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                timezone=self.config.sre.timezone,
            ),
            tags=self.tags,
        )

        # Deploy SRE DNS server
        dns = SREDnsServerComponent(
            "sre_dns_server",
            self.stack_name,
            SREDnsServerProps(
                allow_workspace_internet=self.config.sre.allow_workspace_internet,
                data_collection_endpoint_id=monitoring_elements.data_collection_endpoint.id,
                data_collection_rule_id=monitoring_elements.data_collection_rule_vms.id,
                dockerhub_credentials=dockerhub_credentials,
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                maintenance_configuration_id=monitoring_elements.maintenance_configuration.id,
                shm_fqdn=shm_fqdn,
                timezone=self.config.sre.timezone,
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
                shm_location=shm_location,
                shm_resource_group_name=self.context.resource_group_name,
                shm_subscription_id=shm_subscription_id,
                shm_zone_name=shm_fqdn,
                sre_name=self.config.name,
                use_gitea_mirror=not self.config.sre.allow_workspace_internet
                and len(self.config.user_services.gitea_mirror.repositories) > 0,
                use_software_repositories=not self.config.sre.allow_workspace_internet,
                user_public_ip_ranges=self.config.sre.research_user_ip_addresses,
            ),
            tags=self.tags,
        )

        # Deploy Entra resources
        entra = SREEntraComponent(
            "sre_entra",
            SREEntraProps(
                group_names=ldap_group_names,
                shm_name=self.context.name,
                sre_fqdn=networking.sre_fqdn,
                sre_name=self.config.name,
            ),
        )

        # Deploy monitoring networking
        SREMonitoringComponent(
            "sre_monitoring",
            self.stack_name,
            SREMonitoringNetworkingProps(
                data_collection_endpoint_id=monitoring_elements.data_collection_endpoint.id,
                dns_private_zones=dns.private_zones,
                location=self.config.azure.location,
                log_analytics=monitoring_elements.workspace_analytics.workspace,
                resource_group_name=resource_group.name,
                subnet=networking.subnet_monitoring,
                timezone=self.config.sre.timezone,
            ),
            tags=self.tags,
        )

        # Deploy SRE firewall
        SREFirewallComponent(
            "sre_firewall",
            self.stack_name,
            SREFirewallProps(
                allow_workspace_internet=self.config.sre.allow_workspace_internet,
                location=self.config.azure.location,
                log_analytics_workspace=monitoring_elements.workspace_analytics.workspace,
                resource_group_name=resource_group.name,
                route_table_name=networking.route_table_name,
                subnet_apt_proxy_server=networking.subnet_apt_proxy_server,
                subnet_clamav_mirror=networking.subnet_clamav_mirror,
                subnet_dns_sidecar=networking.subnet_dns_sidecar,
                subnet_firewall=networking.subnet_firewall,
                subnet_firewall_management=networking.subnet_firewall_management,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
                subnet_identity_containers=networking.subnet_identity_containers,
                subnet_user_services_gitea_mirror=networking.subnet_user_services_gitea_mirror,
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
                log_analytics_workspace=monitoring_elements.workspace_analytics.workspace,
                resource_group=resource_group,
                sre_fqdn=networking.sre_fqdn,
                storage_quota_gb_home=self.config.sre.storage_quota_gb.home,
                storage_quota_gb_shared=self.config.sre.storage_quota_gb.shared,
                subnet_data_configuration=networking.subnet_data_configuration,
                subnet_data_private=networking.subnet_data_private,
                subscription_id=self.config.azure.subscription_id,
                subscription_name=sre_subscription_name,
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
                log_analytics_workspace=monitoring_elements.workspace_analytics,
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
                log_analytics_workspace=monitoring_elements.workspace_analytics,
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
                entra_application_id=entra.identity_application_id,
                entra_application_secret=entra.identity_application_secret,
                entra_tenant_id=shm_entra_tenant_id,
                location=self.config.azure.location,
                log_analytics_workspace=monitoring_elements.workspace_analytics,
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
                admin_group_name=ldap_group_names["admin_group_name"],
                allow_copy=self.config.sre.remote_desktop.allow_copy,
                allow_paste=self.config.sre.remote_desktop.allow_paste,
                database_password=data.password_user_database_admin,
                dns_server_ip=dns.ip_address,
                dockerhub_credentials=dockerhub_credentials,
                entra_application_id=entra.remote_desktop_application_id,
                entra_application_url=entra.remote_desktop_url,
                entra_tenant_id=shm_entra_tenant_id,
                ldap_group_filter=ldap_group_filter,
                ldap_group_search_base=ldap_group_search_base,
                ldap_server_hostname=identity.hostname,
                ldap_server_port=identity.server_port,
                ldap_user_filter=ldap_user_filter,
                ldap_user_search_base=ldap_user_search_base,
                location=self.config.azure.location,
                log_analytics_workspace=monitoring_elements.workspace_analytics,
                resource_group_name=resource_group.name,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
                subnet_guacamole_containers_support=networking.subnet_guacamole_containers_support,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
                user_group_name=ldap_group_names["user_group_name"],
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
                db_server_shared_password=data.password_shared_database_admin,
                dns_server_ip=dns.ip_address,
                dockerhub_credentials=dockerhub_credentials,
                ldap_server_hostname=identity.hostname,
                ldap_server_port=identity.server_port,
                ldap_user_filter=ldap_user_filter,
                ldap_username_attribute=ldap_username_attribute,
                ldap_user_search_base=ldap_user_search_base,
                location=self.config.azure.location,
                log_analytics_workspace=monitoring_elements.workspace_analytics,
                nexus_admin_password=data.password_nexus_admin,
                resource_group_name=resource_group.name,
                repository_data=self.config.user_services.gitea_mirror,
                software_packages=self.config.sre.software_packages,
                software_repositories_database_password=data.password_nexus_database_admin,
                sre_fqdn=networking.sre_fqdn,
                nexus_persistent_quota_gb=self.config.user_services.nexus.persistent_quota_gb,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
                subnet_containers=networking.subnet_user_services_containers,
                subnet_containers_support=networking.subnet_user_services_containers_support,
                subnet_gitea_mirrors=networking.subnet_user_services_gitea_mirror,
                subnet_databases=networking.subnet_user_services_databases,
                subnet_software_repositories=networking.subnet_user_services_software_repositories,
                subnet_software_repositories_support=networking.subnet_user_services_software_repositories_support,
            ),
            tags=self.tags,
        )

        # Deploy desired state
        desired_state = SREDesiredStateComponent(
            "sre_desired_state",
            self.stack_name,
            SREDesiredStateProps(
                admin_ip_addresses=self.config.sre.admin_ip_addresses,
                allow_workspace_internet=self.config.sre.allow_workspace_internet,
                clamav_mirror_hostname=clamav_mirror.hostname,
                database_service_admin_password=data.password_database_service_admin,
                dns_private_zones=dns.private_zones,
                gitea_hostname=user_services.gitea_server.hostname,
                hedgedoc_hostname=user_services.hedgedoc_server.hostname,
                ldap_group_filter=ldap_group_filter,
                ldap_group_search_base=ldap_group_search_base,
                ldap_server_hostname=identity.hostname,
                ldap_server_port=identity.server_port,
                ldap_user_filter=ldap_user_filter,
                ldap_user_search_base=ldap_user_search_base,
                location=self.config.azure.location,
                log_analytics_workspace=monitoring_elements.workspace_analytics.workspace,
                resource_group=resource_group,
                software_repository_hostname=(
                    user_services.software_repositories.hostname
                    if hasattr(user_services, "software_repositories")
                    else ""
                ),
                subnet_desired_state=networking.subnet_desired_state,
                subscription_name=sre_subscription_name,
            ),
        )

        # Deploy workspaces
        workspaces = SREWorkspacesComponent(
            "sre_workspaces",
            self.stack_name,
            SREWorkspacesProps(
                admin_password=data.password_workspace_admin,
                apt_proxy_server_hostname=apt_proxy_server.hostname,
                data_collection_rule_id=monitoring_elements.data_collection_rule_vms.id,
                data_collection_endpoint_id=monitoring_elements.data_collection_endpoint.id,
                location=self.config.azure.location,
                maintenance_configuration_id=monitoring_elements.maintenance_configuration.id,
                resource_group_name=resource_group.name,
                sre_name=self.config.name,
                storage_account_desired_state_name=desired_state.storage_account_name,
                storage_account_data_private_user_name=data.storage_account_data_private_user_name,
                storage_account_data_private_sensitive_name=data.storage_account_data_private_sensitive_name,
                subnet_workspaces=networking.subnet_workspaces,
                subscription_name=sre_subscription_name,
                virtual_network=networking.virtual_network,
                vm_details=[
                    (
                        vm_index,
                        vm_size,
                        self.config.sre.storage_quota_gb.data_disk,
                        self.config.sre.storage_quota_gb.os_disk,
                    )
                    for vm_index, vm_size in enumerate(self.config.sre.workspace_skus)
                ],
            ),
            opts=ResourceOptions(depends_on=[desired_state]),
            tags=self.tags,
        )

        # Deploy the DNS Sidecar
        container_instance_information: list[SupportsDnsSidecar] = [
            user_services.gitea_server,
            user_services.hedgedoc_server,
            apt_proxy_server,
            clamav_mirror,
            identity,
        ]
        if hasattr(user_services, "software_repositories"):
            container_instance_information.append(
                user_services.software_repositories,
            )

        DnsSidecarComponent(
            "dns_sidecar",
            self.stack_name,
            DnsSidecarProps(
                container_instances=container_instance_information,
                cron_expression=self.config.user_services.dns_sidecar.cron_expression,
                subnet_id=Output.from_input(networking.subnet_dns_sidecar).apply(
                    get_id_from_subnet
                ),
                log_analytics_workspace=monitoring_elements.workspace_analytics,
                location=self.config.azure.location,
                resource_group_name=resource_group.name,
                replica_timeout=self.config.user_services.dns_sidecar.replica_timeout,
                retry_limit=self.config.user_services.dns_sidecar.retry_limit,
                sre_fqdn=networking.sre_fqdn,
                subscription_id=self.config.azure.subscription_id,
                storage_account_key=data.storage_account_data_configuration_key,
                storage_account_name=data.storage_account_data_configuration_name,
                workload_maximum_count=self.config.user_services.dns_sidecar.workload_maximum_count,
                workload_minimum_count=self.config.user_services.dns_sidecar.workload_minimum_count,
            ),
        )

        # Export values for later use
        if hasattr(user_services, "software_repositories"):
            pulumi.export(
                "allowlist_share_name",
                user_services.software_repositories.allowlist_file_share_name,
            )
            pulumi.export(
                "allowlist_share_filenames",
                user_services.software_repositories.allowlist_file_names,
            )
            pulumi.export(
                "software_repositories", user_services.software_repositories.exports
            )

        pulumi.export("data", data.exports)
        pulumi.export("ldap", ldap_group_names)
        pulumi.export("remote_desktop", remote_desktop.exports)
        pulumi.export("sre_fqdn", networking.sre_fqdn)
        pulumi.export("sre_resource_group", resource_group.name)
        pulumi.export("workspaces", workspaces.exports)
