"""Command-line application for deploying a Data Safe Haven from project files"""
# Standard library imports
import ipaddress
import re
from typing import List, Optional

# Third party imports
import pytz
import yaml
from cleo import Command

# Local imports
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external.api import GraphApi
from data_safe_haven.helpers import password
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.pulumi import PulumiStack
from data_safe_haven.provisioning import SHMProvisioningManager


class DeploySHMCommand(LoggingMixin, Command):
    """
    Deploy a Safe Haven Management component using local configuration files

    shm
        {--a|aad-tenant-id= : Tenant ID for the AzureAD where users will be created}
        {--e|email= : A single email address that your system deployers and administrators can be contacted on}
        {--f|fqdn= : Domain that SHM users will belong to}
        {--i|ip-address=* : IP addresses or ranges that system deployers and administrators will be connecting from}
        {--o|output= : Path to an output log file}
        {--t|timezone= : Timezone to use}
    """

    def handle(self) -> None:
        try:
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenInputException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)
            self.add_missing_values(config)

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

            # Deploy Azure infrastructure
            stack = PulumiStack(config, "SHM")
            # Set Azure options
            stack.add_option("azure-native:location", config.azure.location)
            stack.add_option(
                "azure-native:subscriptionId", config.azure.subscription_id
            )
            stack.add_option("azure-native:tenantId", config.azure.tenant_id)
            # Add necessary secrets
            stack.add_secret("password-domain-admin", password(20))
            stack.add_secret("password-domain-azure-ad-connect", password(20))
            stack.add_secret("password-domain-computer-manager", password(20))
            stack.add_secret("password-domain-ldap-searcher", password(20))
            stack.add_secret("verification-azuread-custom-domain", verification_record)
            # Deploy with Pulumi
            stack.deploy()

            # Add the SHM domain as a custom domain in AzureAD
            graph_api.verify_custom_domain(
                config.shm.fqdn, stack.output("fqdn_nameservers")
            )

            # Add Pulumi infrastructure information to the config file
            with open(stack.local_stack_path, "r", encoding="utf-8") as f_stack:
                stack_yaml = yaml.safe_load(f_stack)
            config.pulumi.stacks[stack.stack_name] = stack_yaml

            # Add Pulumi output information to the config file
            config.shm.domain_controllers = stack.output("domain_controllers")
            config.shm.networking = stack.output("networking")
            config.add_secret(
                config.shm.domain_controllers["azure_ad_connect_password_secret"],
                stack.secret("password-domain-azure-ad-connect"),
            )
            config.add_secret(
                config.shm.domain_controllers["ldap_searcher_password_secret"],
                stack.secret("password-domain-ldap-searcher"),
            )
            config.add_secret(
                config.shm.domain_controllers["domain_admin_password_secret"],
                stack.secret("password-domain-admin"),
            )

            # Upload config to blob storage
            config.upload()

            # Provision SHM with anything that could not be done in Pulumi
            manager = SHMProvisioningManager(config)
            manager.run()

        except DataSafeHavenException as exc:
            error_msg = (
                f"Could not deploy Data Safe Haven Management environment.\n{str(exc)}"
            )
            for line in error_msg.split("\n"):
                self.error(line)

    def add_missing_values(self, config: Config) -> None:
        """Request any missing config values and add them to the config"""
        # Request FQDN if not provided
        fqdn = self.option("fqdn")
        if not isinstance(fqdn, Optional[str]):
            raise DataSafeHavenInputException(f"Invalid value '{fqdn}' provided for option 'fqdn'.")
        while not config.shm.fqdn:
            if fqdn:
                config.shm.fqdn = fqdn
            else:
                fqdn = self.log_ask(
                    "Please enter the domain that SHM users will belong to:", None
                )

        # Request admin IP addresses if not provided
        aad_tenant_id = self.option("aad-tenant-id")
        if not isinstance(aad_tenant_id, Optional[str]):
            raise DataSafeHavenInputException(f"Invalid value '{aad_tenant_id}' provided for option 'aad-tenant-id'.")
        while not config.shm.aad_tenant_id:
            if aad_tenant_id and re.match(
                r"^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$",
                aad_tenant_id,
            ):
                config.shm.aad_tenant_id = aad_tenant_id
            else:
                self.info(
                    "We need to know the tenant ID for the AzureAD where users will be created, for example '10de18e7-b238-6f1e-a4ad-772708929203'."
                )
                aad_tenant_id = self.log_ask("AzureAD tenant ID:", None)

        # Request admin email address if not provided
        admin_email_address = self.option("email")
        if not isinstance(admin_email_address, Optional[str]):
            raise DataSafeHavenInputException(f"Invalid value '{admin_email_address}' provided for option 'email'.")
        while not config.shm.admin_email_address:
            if not admin_email_address:
                self.info(
                    "We need to know an email address that your system deployers and administrators can be contacted on."
                )
                self.info(
                    "Please enter a single email address, for example 'sherlock@holmes.com'."
                )
                admin_email_address = self.log_ask("Administrator email address:", None)
            if admin_email_address:
                config.shm.admin_email_address = str(admin_email_address).strip()
            admin_email_address = None

        # Request admin IP addresses if not provided
        admin_ip_address_list = self.option("ip-address")
        if not isinstance(admin_ip_address_list, Optional[List]):
            raise DataSafeHavenInputException(f"Invalid value '{admin_ip_address_list}' provided for option 'ip-address'.")
        admin_ip_addresses = " ".join(admin_ip_address_list) if admin_ip_address_list else ""
        while not config.shm.admin_ip_addresses:
            if not admin_ip_addresses:
                self.info(
                    "We need to know any IP addresses or ranges that your system deployers and administrators will be connecting from."
                )
                self.info(
                    "Please enter all of them at once, separated by spaces, for example '10.1.1.1  2.2.2.0/24  5.5.5.5'."
                )
                admin_ip_addresses = self.log_ask(
                    "Space-separated administrator IP addresses and ranges:", None
                )
            config.shm.admin_ip_addresses = [
                str(ipaddress.ip_network(ipv4))
                for ipv4 in admin_ip_addresses.split()
                if ipv4
            ]
            admin_ip_addresses = None

        # Request timezone if not provided
        timezone = self.option("timezone")
        if not isinstance(timezone, Optional[str]):
            raise DataSafeHavenInputException(f"Invalid value '{timezone}' provided for option 'timezone'.")
        while not config.shm.timezone:
            if timezone in pytz.all_timezones:
                config.shm.timezone = timezone
            else:
                if timezone:
                    self.error(f"Timezone '{timezone}' not recognised")
                timezone = self.log_ask(
                    "Please enter the timezone that this SHM will use (default: 'Europe/London'):",
                    "Europe/London",
                )
