"""Command-line application for deploying a Secure Research Environment from project files"""
# Third party imports
import yaml
from cleo import Command
from typing import cast, List

# Local imports
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external.api import AzureApi, GraphApi
from data_safe_haven.helpers import alphanumeric, password
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.provisioning import SREProvisioningManager
from data_safe_haven.pulumi import PulumiStack


class DeploySRECommand(LoggingMixin, Command):
    """
    Deploy a Secure Research Environment using local configuration files

    sre
        {name : Name of SRE to deploy}
        {--c|allow-copy= : Allow copying of text from the SRE (default: False)}
        {--p|allow-paste= : Allow pasting of text into the SRE (default: False)}
        {--o|output= : Path to an output log file}
        {--r|research-desktop=* : Add a research desktop VM by SKU name}
    """

    def handle(self) -> None:
        try:
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Require at least one research desktop
            if not self.option("research-desktop"):
                raise ValueError("At least one research desktop must be specified.")

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)

            # Set a JSON-safe name for this SRE and add any missing values to the config
            self.sre_name = alphanumeric(cast(str, self.argument("name")))
            self.add_missing_values(config)

            # Load GraphAPI as this may require user-interaction that is not possible as part of a Pulumi declarative command
            graph_api = GraphApi(
                tenant_id=config.shm.aad_tenant_id,
                default_scopes=["Application.ReadWrite.All", "Group.ReadWrite.All"],
            )

            # Deploy infrastructure with Pulumi
            stack = PulumiStack(config, "SRE", sre_name=self.sre_name)
            # Set Azure options
            stack.add_option("azure-native:location", config.azure.location)
            stack.add_option(
                "azure-native:subscriptionId", config.azure.subscription_id
            )
            stack.add_option("azure-native:tenantId", config.azure.tenant_id)
            # Add necessary secrets
            stack.add_secret(
                "password-domain-ldap-searcher",
                config.get_secret(
                    config.shm.domain_controllers["ldap_searcher_password_secret"]
                ),
                replace=True,
            )
            stack.add_secret("password-user-database-admin", password(20))
            stack.add_secret("password-secure-research-desktop-admin", password(20))
            stack.add_secret("token-azuread-graphapi", graph_api.token, replace=True)
            stack.deploy()

            # Add Pulumi infrastructure information to the config file
            with open(stack.local_stack_path, "r", encoding="utf-8") as f_stack:
                stack_yaml = yaml.safe_load(f_stack)
            config.pulumi.stacks[stack.stack_name] = stack_yaml

            # Add Pulumi output information to the config file
            for key, value in stack.output("remote_desktop").items():
                config.sre[self.sre_name].remote_desktop[key] = value
            config.sre[self.sre_name].remote_desktop[
                "connection_db_server_admin_password_secret"
            ] = f"password-user-database-admin-sre-{self.sre_name}"
            for (vm_name, vm_ipaddress) in zip(
                stack.output("srd")["vm_names"], stack.output("srd")["vm_ip_addresses"]
            ):
                config.sre[self.sre_name].research_desktops[
                    vm_name
                ].ip_address = vm_ipaddress
            config.add_secret(
                config.sre[self.sre_name].remote_desktop[
                    "connection_db_server_admin_password_secret"
                ],
                stack.secret("password-user-database-admin"),
            )

            # Upload config to blob storage
            config.upload()

            # Provision SRE with anything that could not be done in Pulumi
            manager = SREProvisioningManager(config, self.sre_name)
            manager.run()

        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not deploy Secure Research Environment {self.argument('name')}.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)

    def add_missing_values(self, config: Config) -> None:
        """Request any missing config values and add them to the config"""
        # Create a config entry for this SRE if it does not exist
        if self.sre_name not in config.sre.keys():
            highest_index = max([0] + [sre.index for sre in config.sre.values()])
            config.sre[self.sre_name].index = highest_index + 1

        # Set the security group name
        config.sre[
            self.sre_name
        ].security_group_name = f"Data Safe Haven Users SRE {self.sre_name}"

        # Set whether copying is allowed
        config.sre[self.sre_name].remote_desktop.allow_copy = bool(
            self.option("allow-copy")
        )

        # Set whether pasting is allowed
        config.sre[self.sre_name].remote_desktop.allow_paste = bool(
            self.option("allow-paste")
        )

        # Add list of research desktop VMs
        azure_api = AzureApi(config.subscription_name)
        available_vm_skus = azure_api.list_available_vm_skus(config.azure.location)
        vm_skus = [
            sku
            for sku in cast(List[str], self.option("research-desktop"))
            if sku in available_vm_skus
        ]
        while not vm_skus:
            self.warning("An SRE deployment needs at least one research desktop.")
            self.info(
                "Please enter the VM SKU for each desktop you want to create, separated by spaces, for example 'Standard_D2s_v3 Standard_D2s_v3'."
            )
            self.info("Available SKUs can be seen here: https://azureprice.net/")
            answer = self.log_ask("Space-separated VM sizes:", None)
            vm_skus = [sku for sku in answer if sku in available_vm_skus]
        if hasattr(config.sre[self.sre_name], "research_desktops"):
            del config.sre[self.sre_name].research_desktops
        idx_cpu, idx_gpu = 0, 0
        for vm_sku in vm_skus:
            if int(available_vm_skus[vm_sku]["GPUs"]) > 0:
                vm_cfg = config.sre[self.sre_name].research_desktops[
                    f"srd-gpu-{idx_gpu:02d}"
                ]
                idx_gpu += 1
            else:
                vm_cfg = config.sre[self.sre_name].research_desktops[
                    f"srd-cpu-{idx_cpu:02d}"
                ]
                idx_cpu += 1
            vm_cfg.sku = vm_sku
            vm_cfg.cpus = int(available_vm_skus[vm_sku]["vCPUs"])
            vm_cfg.gpus = int(available_vm_skus[vm_sku]["GPUs"])
            vm_cfg.ram = int(available_vm_skus[vm_sku]["MemoryGB"])
