"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
from typing import List
from typing_extensions import Annotated

# Third party imports
import typer

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config, DotFileSettings
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.functions import alphanumeric
from .base_command import BaseCommand


class UsersRegisterCommand(BaseCommand):  # type: ignore
    """Register existing users with a deployed SRE"""

    def entrypoint(
        self,
        usernames: Annotated[
            List[str],
            typer.Argument(
                help="Username of a user to register with this SRE. [*may be specified several times*]",
            ),
        ],
        sre: Annotated[
            str,
            typer.Argument(
                help="The name of the SRE to add the users to.",
            ),
        ],
    ) -> None:
        shm_name = "UNKNOWN"
        sre_name = "UNKNOWN"
        try:
            # Use a JSON-safe SRE name
            sre_name = alphanumeric(sre)

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
            if not sre_name:
                raise DataSafeHavenException("SRE name must be specified.")
            self.logger.info(
                f"Preparing to register {len(usernames)} users with SRE '{sre_name}'"
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
            for username in usernames:
                if username in available_usernames:
                    usernames_to_register.append(username)
                else:
                    self.logger.error(
                        f"Username '{username}' does not belong to this Data Safe Haven deployment. Please use 'dsh users add' to create it."
                    )
            users.register(sre_name, usernames_to_register)
        except DataSafeHavenException as exc:
            raise DataSafeHavenException(
                f"Could not register users from Data Safe Haven '{shm_name}' with SRE '{sre_name}'.\n{str(exc)}"
            ) from exc
