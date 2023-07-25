"""Command-line application for deploying a Data Safe Haven from project files"""
# Standard library imports

# Third party imports
import pytz

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenError,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.functions import password
from data_safe_haven.provisioning import SHMProvisioningManager
from data_safe_haven.pulumi import PulumiSHMStack
from data_safe_haven.utility import Logger


class DeploySHMCommand:
    """Deploy a Safe Haven Management component"""

    def __init__(self):
        """Constructor"""
        self.logger = Logger()

    def __call__(
        self,
        aad_tenant_id: str | None = None,
        admin_email_address: str | None = None,
        admin_ip_addresses: list[str] | None = None,
        fqdn: str | None = None,
        timezone: str | None = None,
    ) -> None:
        """Typer command line entrypoint"""
        try:
            # Load config file
            config = Config()
            self.update_config(
                config,
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
            stack.add_option("azure-native:subscriptionId", config.azure.subscription_id, replace=False)
            stack.add_option("azure-native:tenantId", config.azure.tenant_id, replace=False)
            # Add necessary secrets
            stack.add_secret("password-domain-admin", password(20), replace=False)
            stack.add_secret("password-domain-azure-ad-connect", password(20), replace=False)
            stack.add_secret("password-domain-computer-manager", password(20), replace=False)
            stack.add_secret("password-domain-ldap-searcher", password(20), replace=False)
            stack.add_secret("password-update-server-linux-admin", password(20), replace=False)
            stack.add_secret("verification-azuread-custom-domain", verification_record, replace=False)

            # Deploy Azure infrastructure with Pulumi
            stack.deploy()

            # Add the SHM domain as a custom domain in AzureAD
            graph_api.verify_custom_domain(config.shm.fqdn, stack.output("fqdn_nameservers"))

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

    def update_config(
        self,
        config: Config,
        aad_tenant_id: str | None = None,
        admin_email_address: str | None = None,
        admin_ip_addresses: list[str] | None = None,
        fqdn: str | None = None,
        timezone: str | None = None,
    ) -> None:
        # Update AzureAD tenant ID
        if aad_tenant_id is not None:
            if config.shm.aad_tenant_id and (config.shm.aad_tenant_id != aad_tenant_id):
                self.logger.debug(f"Overwriting existing AzureAD tenant ID {config.shm.aad_tenant_id}")
            self.logger.info(f"Setting [bold]AzureAD tenant ID[/] to [green]{aad_tenant_id}[/].")
            config.shm.aad_tenant_id = aad_tenant_id
        if not config.shm.aad_tenant_id:
            msg = "No AzureAD tenant ID was found. Use [bright_cyan]'--aad-tenant-id / -a'[/] to set one."
            raise DataSafeHavenConfigError(msg)

        # Update admin email address
        if admin_email_address is not None:
            if config.shm.admin_email_address and (config.shm.admin_email_address != admin_email_address):
                self.logger.debug(f"Overwriting existing admin email address {config.shm.admin_email_address}")
            self.logger.info(f"Setting [bold]admin email address[/] to [green]{admin_email_address}[/].")
            config.shm.admin_email_address = admin_email_address
        if not config.shm.admin_email_address:
            msg = "No admin email address was found. Use [bright_cyan]'--email / -e'[/] to set one."
            raise DataSafeHavenConfigError(msg)

        # Update admin IP addresses
        if admin_ip_addresses:
            if config.shm.admin_ip_addresses and (config.shm.admin_ip_addresses != admin_ip_addresses):
                self.logger.debug(f"Overwriting existing admin IP addresses {config.shm.admin_ip_addresses}")
            self.logger.info(f"Setting [bold]admin IP addresses[/] to [green]{admin_ip_addresses}[/].")
            config.shm.admin_ip_addresses = admin_ip_addresses
        if len(config.shm.admin_ip_addresses) == 0:
            msg = "No admin IP addresses were found. Use [bright_cyan]'--ip-address / -i'[/] to set one."
            raise DataSafeHavenConfigError(msg)

        # Update FQDN
        if fqdn is not None:
            if config.shm.fqdn and (config.shm.fqdn != fqdn):
                self.logger.debug(f"Overwriting existing fully-qualified domain name {config.shm.fqdn}")
            self.logger.info(f"Setting [bold]fully-qualified domain name[/] to [green]{fqdn}[/].")
            config.shm.fqdn = fqdn
        if not config.shm.fqdn:
            msg = "No fully-qualified domain name was found. Use [bright_cyan]'--fqdn / -f'[/] to set one."
            raise DataSafeHavenConfigError(msg)

        # Update timezone if it passes validation
        if timezone is not None:
            if timezone not in pytz.all_timezones:
                self.logger.error(f"Invalid value '{timezone}' provided for 'timezone'.")
            else:
                if config.shm.timezone and (config.shm.timezone != timezone):
                    self.logger.debug(f"Overwriting existing timezone {config.shm.timezone}")
                self.logger.info(f"Setting [bold]timezone[/] to [green]{timezone}[/].")
                config.shm.timezone = timezone
        if not config.shm.timezone:
            msg = "No timezone was found. Use [bright_cyan]'--timezone / -t'[/] to set one."
            raise DataSafeHavenConfigError(msg)
