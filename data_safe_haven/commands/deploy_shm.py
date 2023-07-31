"""Deploy a Safe Haven Management component"""
from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import GraphApi
from data_safe_haven.functions import password
from data_safe_haven.provisioning import SHMProvisioningManager
from data_safe_haven.pulumi import PulumiSHMStack


def deploy_shm(
    *,
    aad_tenant_id: str | None = None,
    admin_email_address: str | None = None,
    admin_ip_addresses: list[str] | None = None,
    fqdn: str | None = None,
    timezone: str | None = None,
) -> None:
    """Deploy a Safe Haven Management component"""
    try:
        # Load config file
        config = Config()
        config.shm.update(
            aad_tenant_id=aad_tenant_id,
            admin_email_address=admin_email_address,
            admin_ip_addresses=admin_ip_addresses,
            fqdn=fqdn,
            timezone=timezone,
        )

        # Add the SHM domain to AzureAD as a custom domain
        graph_api = GraphApi(
            tenant_id=config.shm.aad_tenant_id,
            default_scopes=[
                "Application.ReadWrite.All",
                "Domain.ReadWrite.All",
                "Group.ReadWrite.All",
            ],
        )
        verification_record = graph_api.add_custom_domain(config.shm.fqdn)

        # Initialise Pulumi stack
        stack = PulumiSHMStack(config)
        # Set Azure options
        stack.add_option("azure-native:location", config.azure.location, replace=False)
        stack.add_option(
            "azure-native:subscriptionId",
            config.azure.subscription_id,
            replace=False,
        )
        stack.add_option("azure-native:tenantId", config.azure.tenant_id, replace=False)
        # Add necessary secrets
        stack.add_secret("password-domain-admin", password(20), replace=False)
        stack.add_secret(
            "password-domain-azure-ad-connect", password(20), replace=False
        )
        stack.add_secret(
            "password-domain-computer-manager", password(20), replace=False
        )
        stack.add_secret("password-domain-ldap-searcher", password(20), replace=False)
        stack.add_secret(
            "password-update-server-linux-admin", password(20), replace=False
        )
        stack.add_secret(
            "verification-azuread-custom-domain", verification_record, replace=False
        )

        # Deploy Azure infrastructure with Pulumi
        stack.deploy()

        # Add the SHM domain as a custom domain in AzureAD
        graph_api.verify_custom_domain(
            config.shm.fqdn, stack.output("fqdn_nameservers")
        )

        # Add Pulumi infrastructure information to the config file
        config.read_stack(stack.stack_name, stack.local_stack_path)

        # Upload config to blob storage
        config.upload()

        # Provision SHM with anything that could not be done in Pulumi
        manager = SHMProvisioningManager(
            subscription_name=config.subscription_name,
            stack=stack,
        )
        manager.run()
    except DataSafeHavenError as exc:
        msg = f"Could not deploy Data Safe Haven Management environment.\n{exc}"
        raise DataSafeHavenError(msg) from exc
