"""Command-line application for initialising a Data Safe Haven deployment"""
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import GraphApi
from data_safe_haven.utility import Logger


class UsersRemoveCommand:
    """Remove existing users from a deployed Data Safe Haven"""

    def __init__(self):
        """Constructor"""
        self.logger = Logger()

    def __call__(
        self,
        usernames: list[str],
    ) -> None:
        shm_name = "UNKNOWN"
        try:
            # Load config file
            config = Config()
            shm_name = config.name

            # Load GraphAPI as this may require user-interaction that is not
            # possible as part of a Pulumi declarative command
            graph_api = GraphApi(
                tenant_id=config.shm.aad_tenant_id,
                default_scopes=["Group.Read.All"],
            )

            # Remove users from SHM
            if usernames:
                users = UserHandler(config, graph_api)
                users.remove(usernames)
        except DataSafeHavenError as exc:
            for (
                line
            ) in f"Could not remove users from Data Safe Haven '{shm_name}'.\n{exc}".split(
                "\n"
            ):
                self.logger.error(line)
