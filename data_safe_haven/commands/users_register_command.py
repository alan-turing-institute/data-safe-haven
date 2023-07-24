"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
from typing import List

# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config
from data_safe_haven.exceptions import (
    DataSafeHavenException,
)
from data_safe_haven.external import GraphApi
from data_safe_haven.functions import alphanumeric
from data_safe_haven.utility import Logger


class UsersRegisterCommand:
    """Register existing users with a deployed SRE"""

    def __init__(self):
        """Constructor"""
        self.logger = Logger()

    def __call__(
        self,
        usernames: list[str],
        sre: str,
    ) -> None:
        shm_name = "UNKNOWN"
        sre_name = "UNKNOWN"
        try:
            # Use a JSON-safe SRE name
            sre_name = alphanumeric(sre).lower()

            # Load config file
            config = Config()
            shm_name = config.name

            # Check that SRE option has been provided
            if not sre_name:
                msg = "SRE name must be specified."
                raise DataSafeHavenException(msg)
            self.logger.info(f"Preparing to register {len(usernames)} users with SRE '{sre_name}'")

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
            msg = f"Could not register users from Data Safe Haven '{shm_name}' with SRE '{sre_name}'.\n{exc!s}"
            raise DataSafeHavenException(
                msg
            ) from exc
