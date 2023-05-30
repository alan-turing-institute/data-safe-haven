"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
from typing import List, Optional

# Third party imports
from cleo import Command

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external.api import GraphApi
from data_safe_haven.mixins import LoggingMixin


class UsersRegisterCommand(LoggingMixin, Command):  # type: ignore
    """
    Register existing users from a Data Safe Haven deployment with an SRE

    register
        {usernames* : Usernames of users to register with this SRE}
        {--o|output= : Path to an output log file}
        {--s|sre= : Name of SRE to add users to}
    """

    output: Optional[str]
    sre_name: Optional[str]
    usernames: List[str]

    def handle(self) -> int:
        shm_name = "UNKNOWN"
        try:
            # Process command line arguments
            self.process_arguments()

            # Set up logging for anything called by this command
            self.initialise_logging(self.io.verbosity, self.output)

            # Use dotfile settings to load the job configuration
            try:
                settings = DotFileSettings()
            except DataSafeHavenException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)
            shm_name = config.name

            # Check that SRE option has been provided
            if not self.sre_name:
                raise DataSafeHavenException("SRE name must be specified.")
            self.info(
                f"Preparing to register {len(self.usernames)} users with SRE '{self.sre_name}'"
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
            for username in self.usernames:
                if username in available_usernames:
                    usernames_to_register.append(username)
                else:
                    self.error(
                        f"Username '{username}' does not belong to this Data Safe Haven deployment. Please use 'dsh users add' to create it."
                    )
            users.register(self.sre_name, usernames_to_register)
            return 0
        except DataSafeHavenException as exc:
            for (
                line
            ) in f"Could not register users from Data Safe Haven '{shm_name}' with SRE '{self.sre_name}'.\n{str(exc)}".split(
                "\n"
            ):
                self.error(line)
        return 1

    def process_arguments(self) -> None:
        """Load command line arguments into attributes"""
        # Output
        output = self.option("output")
        if not isinstance(output, str) and (output is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{output}' provided for 'output'."
            )
        self.output = output
        # SRE name
        sre_name = self.option("sre")
        if not isinstance(sre_name, str) and (sre_name is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{sre_name}' provided for 'sre'."
            )
        self.sre_name = sre_name
        # Usernames
        usernames = self.argument("usernames")
        if not isinstance(usernames, list) and (usernames is not None):
            raise DataSafeHavenInputException(
                f"Invalid value '{usernames}' provided for 'usernames'."
            )
        self.usernames = usernames if usernames else []
