"""Command-line application for initialising a Data Safe Haven deployment"""
# Local imports
from data_safe_haven.administration.users import UserHandler
from data_safe_haven.config import BackendSettings, Config
from data_safe_haven.exceptions import (
    DataSafeHavenException,
    DataSafeHavenInputException,
)
from data_safe_haven.external import GraphApi


class UsersListCommand:
    """List users from a deployed Data Safe Haven"""

    def __call__(self) -> None:
        shm_name = "UNKNOWN"
        try:
            # Use dotfile settings to load the job configuration
            try:
                settings = BackendSettings()
            except DataSafeHavenException as exc:
                raise DataSafeHavenInputException(
                    f"Unable to load project settings. Please run this command from inside the project directory.\n{str(exc)}"
                ) from exc
            config = Config(settings.name, settings.subscription_name)
            shm_name = config.name

            # Load GraphAPI as this may require user-interaction that is not possible as part of a Pulumi declarative command
            graph_api = GraphApi(
                tenant_id=config.shm.aad_tenant_id,
                default_scopes=["Directory.Read.All", "Group.Read.All"],
            )

            # List users from all sources
            users = UserHandler(config, graph_api)
            users.list()
        except DataSafeHavenException as exc:
            raise DataSafeHavenException(
                f"Could not list users for Data Safe Haven '{shm_name}'.\n{str(exc)}"
            ) from exc
