"""Command-line application for initialising a Data Safe Haven deployment"""
# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.mixins import LoggingMixin


class UsersRegisterCommand(LoggingMixin, Command):
    """
    Register existing users from a Data Safe Haven deployment with an SRE

    register
        {usernames* : Usernames of users to register with this SRE}
        {--o|output= : Path to an output log file}
        {--s|sre= : Name of SRE to add users to}
    """

    def handle(self):
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

            # Check that SRE option has been provided
            if not self.option("sre"):
                raise DataSafeHavenException("SRE name must be specified.")
            self.info(
                f"Preparing to register {len(self.argument('usernames'))} users with SRE '{self.option('sre')}'"
            )

            # Load GraphAPI as this may require user-interaction that is not possible as part of a Pulumi declarative command
            graph_api = GraphApi(
                tenant_id=config.shm.aad_tenant_id,
                default_scopes=["Group.Read.All"],
            )

            # List users
            users = UserHandler(config, graph_api)
            available_usernames = users.get_usernames_domain_controller()
            usernames_to_register = []
            for username in self.argument("usernames"):
                if username in available_usernames:
                    usernames_to_register.append(username)
                else:
                    self.error(
                        f"Username '{username}' does not belong to this Data Safe Haven deployment. Please use 'dsh users add' to create it."
                    )
            users.register(self.option("sre"), usernames_to_register)
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not register users from Data Safe Haven '{config.name}' with SRE '{self.option('sre')}'.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
