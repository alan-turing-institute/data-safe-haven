"""Deploy a Secure Research Environment component"""
from data_safe_haven.config import Config
from data_safe_haven.exceptions import (
    DataSafeHavenError,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.functions import alphanumeric, password
from data_safe_haven.provisioning import SREProvisioningManager
from data_safe_haven.pulumi import PulumiSHMStack, PulumiSREStack
from data_safe_haven.utility import SoftwarePackageCategory


def deploy_sre(
    name: str,
    *,
    allow_copy: bool | None = None,
    allow_paste: bool | None = None,
    data_provider_ip_addresses: list[str] | None = None,
    research_desktop_skus: list[str] | None = None,
    software_packages: SoftwarePackageCategory | None = None,
    user_ip_addresses: list[str] | None = None,
) -> None:
    """Deploy a Secure Research Environment component"""
    sre_name = "UNKNOWN"
    try:
        # Use a JSON-safe SRE name
        sre_name = alphanumeric(name).lower()

        # Load config file
        config = Config()
        config.sre(sre_name).update(
            allow_copy=allow_copy,
            allow_paste=allow_paste,
            data_provider_ip_addresses=data_provider_ip_addresses,
            research_desktop_skus=research_desktop_skus,
            software_packages=software_packages,
            user_ip_addresses=user_ip_addresses,
        )

        # Load GraphAPI as this may require user-interaction that is not
        # possible as part of a Pulumi declarative command
        graph_api = GraphApi(
            tenant_id=config.shm.aad_tenant_id,
            default_scopes=["Application.ReadWrite.All", "Group.ReadWrite.All"],
        )

        # Initialise Pulumi stack
        shm_stack = PulumiSHMStack(config)
        stack = PulumiSREStack(config, sre_name)
        # Set Azure options
        stack.add_option("azure-native:location", config.azure.location, replace=False)
        stack.add_option(
            "azure-native:subscriptionId",
            config.azure.subscription_id,
            replace=False,
        )
        stack.add_option("azure-native:tenantId", config.azure.tenant_id, replace=False)
        # Load SHM stack outputs
        stack.add_option(
            "shm-domain_controllers-domain_sid",
            shm_stack.output("domain_controllers")["domain_sid"],
            replace=True,
        )
        stack.add_option(
            "shm-domain_controllers-ldap_root_dn",
            shm_stack.output("domain_controllers")["ldap_root_dn"],
            replace=True,
        )
        stack.add_option(
            "shm-domain_controllers-ldap_server_ip",
            shm_stack.output("domain_controllers")["ldap_server_ip"],
            replace=True,
        )
        stack.add_option(
            "shm-domain_controllers-netbios_name",
            shm_stack.output("domain_controllers")["netbios_name"],
            replace=True,
        )
        stack.add_option(
            "shm-monitoring-automation_account_name",
            shm_stack.output("monitoring")["automation_account_name"],
            replace=True,
        )
        stack.add_option(
            "shm-monitoring-log_analytics_workspace_id",
            shm_stack.output("monitoring")["log_analytics_workspace_id"],
            replace=True,
        )
        stack.add_secret(
            "shm-monitoring-log_analytics_workspace_key",
            shm_stack.output("monitoring")["log_analytics_workspace_key"],
            replace=True,
        )
        stack.add_option(
            "shm-monitoring-resource_group_name",
            shm_stack.output("monitoring")["resource_group_name"],
            replace=True,
        )
        stack.add_option(
            "shm-networking-private_dns_zone_base_id",
            shm_stack.output("networking")["private_dns_zone_base_id"],
            replace=True,
        )
        stack.add_option(
            "shm-networking-resource_group_name",
            shm_stack.output("networking")["resource_group_name"],
            replace=True,
        )
        stack.add_option(
            "shm-networking-subnet_identity_servers_prefix",
            shm_stack.output("networking")["subnet_identity_servers_prefix"],
            replace=True,
        )
        stack.add_option(
            "shm-networking-subnet_subnet_monitoring_prefix",
            shm_stack.output("networking")["subnet_monitoring_prefix"],
            replace=True,
        )
        stack.add_option(
            "shm-networking-subnet_update_servers_prefix",
            shm_stack.output("networking")["subnet_update_servers_prefix"],
            replace=True,
        )
        stack.add_option(
            "shm-networking-virtual_network_name",
            shm_stack.output("networking")["virtual_network_name"],
            replace=True,
        )
        stack.add_option(
            "shm-update_servers-ip_address_linux",
            shm_stack.output("update_servers")["ip_address_linux"],
            replace=True,
        )
        # Add necessary secrets
        stack.copy_secret("password-domain-ldap-searcher", shm_stack)
        stack.add_secret("password-gitea-database-admin", password(20), replace=False)
        stack.add_secret(
            "password-hedgedoc-database-admin", password(20), replace=False
        )
        stack.add_secret("password-nexus-admin", password(20), replace=False)
        stack.add_secret("password-user-database-admin", password(20), replace=False)
        stack.add_secret(
            "password-secure-research-desktop-admin", password(20), replace=False
        )
        stack.add_secret("token-azuread-graphapi", graph_api.token, replace=True)

        # Deploy Azure infrastructure with Pulumi
        stack.deploy()

        # Add Pulumi infrastructure information to the config file
        config.read_stack(stack.stack_name, stack.local_stack_path)

        # Upload config to blob storage
        config.upload()

        # Provision SRE with anything that could not be done in Pulumi
        manager = SREProvisioningManager(
            shm_stack=shm_stack,
            sre_name=sre_name,
            sre_stack=stack,
            subscription_name=config.subscription_name,
            timezone=config.shm.timezone,
        )
        manager.run()
    except DataSafeHavenError as exc:
        msg = f"Could not deploy Secure Research Environment {sre_name}.\n{exc}"
        raise DataSafeHavenError(msg) from exc
