"""Command-line application for deploying a Secure Research Environment from project files"""
# Standard library imports
import ipaddress
from typing import Any, Dict, List, Optional

# Third party imports
import yaml
from cleo import Command

# Local imports
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external.api import AzureApi, GraphApi
from data_safe_haven.helpers import alphanumeric, password
from data_safe_haven.mixins import Logger
from data_safe_haven.provisioning import SREProvisioningManager
from data_safe_haven.pulumi import PulumiStack


class DeploySRECommand(Command):  # type: ignore
    """
    Deploy a Secure Research Environment using local configuration files

    sre
        {name : Name of SRE to deploy}
        {--c|allow-copy= : Allow copying of text from the SRE (default: False)}
        {--d|data-ip-address=* : IP addresses or ranges that data providers will be connecting from}
        {--o|output= : Path to an output log file}
        {--p|allow-paste= : Allow pasting of text into the SRE (default: False)}
        {--r|research-desktop=* : Add a research desktop VM by SKU name}
        {--s|software-packages= : Select what category of software packages users can install ("any", "pre-approved", "none")}
        {--u|user-ip-address=* : IP addresses or ranges that users will be connecting from}
    """

    allow_copy: Optional[bool]
    allow_paste: Optional[bool]
    available_vm_skus: Dict[str, Dict[str, Any]]
    data_provider_ip_address_list: Optional[List[str]]
    output: Optional[str]
    research_desktop_skus: Optional[List[str]]
    research_user_ip_address_list: Optional[List[str]]
    software_packages: Optional[str]

    def handle(self) -> int:
        try:
            # Process command line arguments
            self.process_arguments()

            # Set up logging for anything called by this command
            self.logger = Logger(self.io.verbosity, self.output)

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)

            # Load available VM SKUs for this region
            azure_api = AzureApi(config.subscription_name)
            self.available_vm_skus = azure_api.list_available_vm_skus(
                config.azure.location
            )

            # Add any missing values to the config
            self.add_missing_values(config)

            # Load GraphAPI as this may require user-interaction that is not possible as part of a Pulumi declarative command
            graph_api = GraphApi(
                tenant_id=config.shm.aad_tenant_id,
                default_scopes=["Application.ReadWrite.All", "Group.ReadWrite.All"],
            )

            # Initialise Pulumi stack
            shm_stack = PulumiStack(config, "SHM")
            stack = PulumiStack(config, "SRE", sre_name=self.sre_name)
            # Set Azure options
            stack.add_option("azure-native:location", config.azure.location)
            stack.add_option(
                "azure-native:subscriptionId", config.azure.subscription_id
            )
            stack.add_option("azure-native:tenantId", config.azure.tenant_id)
            # Load SHM stack outputs
            stack.add_option(
                "shm-domain_controllers-domain_sid",
                shm_stack.output("domain_controllers")["domain_sid"],
                True,
            )
            stack.add_option(
                "shm-domain_controllers-ldap_root_dn",
                shm_stack.output("domain_controllers")["ldap_root_dn"],
                True,
            )
            stack.add_option(
                "shm-domain_controllers-ldap_server_ip",
                shm_stack.output("domain_controllers")["ldap_server_ip"],
                True,
            )
            stack.add_option(
                "shm-domain_controllers-netbios_name",
                shm_stack.output("domain_controllers")["netbios_name"],
                True,
            )
            stack.add_option(
                "shm-monitoring-automation_account_name",
                shm_stack.output("monitoring")["automation_account_name"],
                True,
            )
            stack.add_option(
                "shm-monitoring-log_analytics_workspace_id",
                shm_stack.output("monitoring")["log_analytics_workspace_id"],
                True,
            )
            stack.add_secret(
                "shm-monitoring-log_analytics_workspace_key",
                shm_stack.output("monitoring")["log_analytics_workspace_key"],
                True,
            )
            stack.add_option(
                "shm-monitoring-resource_group_name",
                shm_stack.output("monitoring")["resource_group_name"],
                True,
            )
            stack.add_option(
                "shm-networking-private_dns_zone_base_id",
                shm_stack.output("networking")["private_dns_zone_base_id"],
                True,
            )
            stack.add_option(
                "shm-networking-resource_group_name",
                shm_stack.output("networking")["resource_group_name"],
                True,
            )
            stack.add_option(
                "shm-networking-subnet_identity_servers_prefix",
                shm_stack.output("networking")["subnet_identity_servers_prefix"],
                True,
            )
            stack.add_option(
                "shm-networking-subnet_subnet_monitoring_prefix",
                shm_stack.output("networking")["subnet_monitoring_prefix"],
                True,
            )
            stack.add_option(
                "shm-networking-subnet_update_servers_prefix",
                shm_stack.output("networking")["subnet_update_servers_prefix"],
                True,
            )
            stack.add_option(
                "shm-networking-virtual_network_name",
                shm_stack.output("networking")["virtual_network_name"],
                True,
            )
            stack.add_option(
                "shm-update_servers-ip_address_linux",
                shm_stack.output("update_servers")["ip_address_linux"],
                True,
            )
            # Add necessary secrets
            stack.copy_secret("password-domain-ldap-searcher", shm_stack)
            stack.add_secret("password-gitea-database-admin", password(20))
            stack.add_secret("password-hedgedoc-database-admin", password(20))
            stack.add_secret("password-nexus-admin", password(20))
            stack.add_secret("password-user-database-admin", password(20))
            stack.add_secret("password-secure-research-desktop-admin", password(20))
            stack.add_secret("token-azuread-graphapi", graph_api.token, replace=True)

            # Deploy Azure infrastructure with Pulumi
            stack.deploy()

            # Add Pulumi infrastructure information to the config file
            with open(stack.local_stack_path, "r", encoding="utf-8") as f_stack:
                stack_yaml = yaml.safe_load(f_stack)
            config.pulumi.stacks[stack.stack_name] = stack_yaml

            # Upload config to blob storage
            config.upload()

            # Provision SRE with anything that could not be done in Pulumi
            manager = SREProvisioningManager(
                available_vm_skus=self.available_vm_skus,
                shm_stack=shm_stack,
                sre_name=self.sre_name,
                sre_stack=stack,
                subscription_name=config.subscription_name,
                timezone=config.shm.timezone,
            )
            manager.run()
            return 0

        except DataSafeHavenException as exc:
            exception_text = f"Could not deploy Secure Research Environment {self.sre_name}.\n{str(exc)}"
        except Exception as exc:
            exception_text = f"Uncaught exception of type '{type(exc)}'.\n{str(exc)}"
        for line in exception_text.split("\n"):
            self.logger.error(line)
        return 1

    def add_missing_values(self, config: Config) -> None:
        """Request any missing config values and add them to the config"""
        # Create a config entry for this SRE if it does not exist
        if self.sre_name not in config.sre.keys():
            highest_index = max([0] + [sre.index for sre in config.sre.values()])
            config.sre[self.sre_name].index = highest_index + 1

        # Set whether copying is allowed
        while not isinstance(config.sre[self.sre_name].remote_desktop.allow_copy, bool):
            if not self.allow_copy:
                self.allow_copy = self.logger.confirm(
                    "Should users be allowed to copy text out of the SRE?", False
                )
            config.sre[self.sre_name].remote_desktop.allow_copy = self.allow_copy

        # Set whether pasting is allowed
        while not isinstance(
            config.sre[self.sre_name].remote_desktop.allow_paste, bool
        ):
            if not self.allow_paste:
                self.allow_paste = self.logger.confirm(
                    "Should users be allowed to paste text into the SRE?", False
                )
            config.sre[self.sre_name].remote_desktop.allow_paste = self.allow_paste

        # Select which software packages can be installed by users
        while not isinstance(config.sre[self.sre_name].software_packages, str):
            if not self.software_packages:
                self.software_packages = self.logger.choose(
                    "Which packages should users be allowed to install from CRAN/PyPI?",
                    choices=["any", "pre-approved", "none"],
                )
            config.sre[self.sre_name].software_packages = self.software_packages

        # Request data provider IP addresses if not provided
        data_provider_ip_addresses: Optional[str] = (
            " ".join(self.data_provider_ip_address_list)
            if self.data_provider_ip_address_list
            else None
        )
        while not config.sre[self.sre_name].data_provider_ip_addresses:
            if not data_provider_ip_addresses:
                self.logger.info(
                    "We need to know any IP addresses or ranges that your data providers will be connecting from."
                )
                self.logger.info(
                    "Please enter all of them at once, separated by spaces, for example '10.1.1.1  2.2.2.0/24  5.5.5.5'."
                )
                data_provider_ip_addresses = self.logger.ask(
                    "Space-separated data provider IP addresses and ranges:", None
                )
            config.sre[self.sre_name].data_provider_ip_addresses = [
                str(ipaddress.ip_network(ipv4))
                for ipv4 in data_provider_ip_addresses.split()
                if ipv4
            ]
            data_provider_ip_addresses = None

        # Request research user IP addresses if not provided
        research_user_ip_addresses: Optional[str] = (
            " ".join(self.research_user_ip_address_list)
            if self.research_user_ip_address_list
            else None
        )
        while not config.sre[self.sre_name].research_user_ip_addresses:
            if not research_user_ip_addresses:
                self.logger.info(
                    "We need to know any IP addresses or ranges that your research users will be connecting from."
                )
                self.logger.info(
                    "Please enter all of them at once, separated by spaces, for example '10.1.1.1  2.2.2.0/24  5.5.5.5'."
                )
                research_user_ip_addresses = self.logger.ask(
                    "Space-separated research user IP addresses and ranges:", None
                )
            config.sre[self.sre_name].research_user_ip_addresses = [
                str(ipaddress.ip_network(ipv4))
                for ipv4 in research_user_ip_addresses.split()
                if ipv4
            ]
            research_user_ip_addresses = None

        # Get the list of research desktop VMs to deploy
        while not self.research_desktop_skus:
            self.logger.warning(
                "An SRE deployment needs at least one research desktop."
            )
            self.logger.info(
                "Please enter the VM SKU for each desktop you want to create, separated by spaces, for example 'Standard_D2s_v3 Standard_D2s_v3'."
            )
            self.logger.info("Available SKUs can be seen here: https://azureprice.net/")
            candidate_skus = self.logger.ask("Space-separated VM sizes:", None)
            self.research_desktop_skus = [
                sku for sku in candidate_skus.split() if sku in self.available_vm_skus
            ]
        # Construct VM details
        idx_cpu, idx_gpu = 0, 0
        config.sre[self.sre_name].research_desktops = {}
        for vm_sku in self.research_desktop_skus:
            if int(self.available_vm_skus[vm_sku]["GPUs"]) > 0:
                vm_name = f"srd-gpu-{idx_gpu:02d}"
                idx_gpu += 1
            else:
                vm_name = f"srd-cpu-{idx_cpu:02d}"
                idx_cpu += 1
            config.sre[self.sre_name].research_desktops[vm_name] = {
                "sku": vm_sku,
            }

    def process_arguments(self) -> None:
        """Load command line arguments into attributes"""
        # Allow copy
        allow_copy = self.option("allow-copy")
        if not isinstance(allow_copy, bool) and (allow_copy is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{allow_copy}' provided for 'allow-copy'."
            )
        self.allow_copy = allow_copy
        # Allow paste
        allow_paste = self.option("allow-paste")
        if not isinstance(allow_paste, bool) and (allow_paste is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{allow_paste}' provided for 'allow-paste'."
            )
        self.allow_paste = allow_paste
        # Data provider IP addresses
        data_provider_ip_address_list = self.option("data-ip-address")
        if not isinstance(data_provider_ip_address_list, list) and (
            data_provider_ip_address_list is not None
        ):
            raise DataSafeHavenInputException(
                f"Invalid value '{data_provider_ip_address_list}' provided for 'data-ip-address'."
            )
        self.data_provider_ip_address_list = data_provider_ip_address_list
        # Select which software packages can be installed by users
        software_packages = self.option("software-packages")
        if not isinstance(software_packages, str) and (software_packages is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{software_packages}' provided for 'software-packages'."
            )
        self.software_packages = software_packages
        # Research user IP addresses
        research_user_ip_address_list = self.option("user-ip-address")
        if not isinstance(research_user_ip_address_list, list) and (
            research_user_ip_address_list is not None
        ):
            raise DataSafeHavenInputException(
                f"Invalid value '{research_user_ip_address_list}' provided for 'user-ip-address'."
            )
        self.research_user_ip_address_list = research_user_ip_address_list
        # Output
        output = self.option("output")
        if not isinstance(output, str) and (output is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{output}' provided for 'output'."
            )
        self.output = output
        # Research desktops
        research_desktop_skus = self.option("research-desktop")
        if not isinstance(research_desktop_skus, list) and (
            research_desktop_skus is not None
        ):
            raise DataSafeHavenInputException(
                f"Invalid value '{research_desktop_skus}' provided for 'research-desktop'."
            )
        self.research_desktop_skus = research_desktop_skus
        # Set a JSON-safe name for this SRE
        sre_name = self.argument("name")
        if not isinstance(sre_name, str):
            raise DataSafeHavenInputException(
                f"Invalid value '{sre_name}' provided for 'name'."
            )
        self.sre_name = alphanumeric(sre_name)
