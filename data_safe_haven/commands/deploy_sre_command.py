"""Command-line application for deploying a Secure Research Environment from project files"""
# Third party imports
import yaml
from cleo import Command

# Local imports
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.configuration import SREConfigurationManager
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.helpers import alphanumeric, password
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.pulumi import PulumiStack


class DeploySRECommand(LoggingMixin, Command):
    """
    Deploy a Secure Research Environment using local configuration files

    sre
        {name : Name of SRE to deploy}
        {--c|allow-copy= : Allow copying of text from the SRE (default: False)}
        {--p|allow-paste= : Allow pasting of text into the SRE (default: False)}
        {--o|output= : Path to an output log file}
    """

    def handle(self) -> None:
        try:
            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.option("output"))

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)

            # Set a JSON-safe name for this SRE and add any missing values to the config
            self.safe_name = alphanumeric(self.argument("name"))
            self.add_missing_values(config)

            # Load GraphAPI as this may require user-interaction that is not possible as part of a Pulumi declarative command
            graph_api = GraphApi(
                tenant_id=config.shm.aad_tenant_id,
                default_scopes=["Application.ReadWrite.All", "Group.ReadWrite.All"],
            )

            # Deploy infrastructure with Pulumi
            stack = PulumiStack(config, "SRE", sre_name=self.argument("name"))
            # Set Azure options
            stack.add_option("azure-native:location", config.azure.location)
            stack.add_option(
                "azure-native:subscriptionId", config.azure.subscription_id
            )
            stack.add_option("azure-native:tenantId", config.azure.tenant_id)
            # Add necessary secrets
            stack.add_secret("password-user-database-admin", password(20))
            stack.add_secret("token-azuread-graphapi", graph_api.token, replace=True)
            stack.deploy()

            # Add Pulumi infrastructure information to the config file
            with open(stack.local_stack_path, "r") as f_stack:
                stack_yaml = yaml.safe_load(f_stack)
            config.pulumi.stacks[stack.stack_name] = stack_yaml

            # Upload config to blob storage
            config.upload()

            # Apply SRE configuration
            remote_desktop_params = dict(**stack.output("remote_desktop"))
            remote_desktop_params.update(
                {
                    "disable_copy": config.sre[self.safe_name].allow_copy,
                    "disable_paste": config.sre[self.safe_name].allow_paste,
                    "timezone": config.shm.timezone,
                }
            )
            manager = SREConfigurationManager(
                connection_db_server_password=stack.secret(
                    "password-user-database-admin"
                ),
                remote_desktop_params=stack.output("remote_desktop"),
                subscription_name=config.subscription_name,
                vm_params=stack.output("vm_details"),
            )
            manager.apply_configuration()

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
        if self.safe_name not in config.sre.keys():
            highest_index = max([0] + [sre.index for sre in config.sre.values()])
            config.sre[self.safe_name].index = highest_index + 1

        # Set whether copying is allowed
        config.sre[self.safe_name].allow_copy = bool(self.option("allow-copy"))

        # Set whether pasting is allowed
        config.sre[self.safe_name].allow_paste = bool(self.option("allow-paste"))
