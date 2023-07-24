# Standard library imports
import pathlib
from collections.abc import Sequence
from typing import Any

from data_safe_haven.administration.users.research_user import ResearchUser

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.external import AzurePostgreSQLDatabase
from data_safe_haven.pulumi import PulumiSREStack


class GuacamoleUsers:
    def __init__(self, config: Config, sre_name: str, *args: Any, **kwargs: Any):
        super().__init__(*args, **kwargs)
        sre_stack = PulumiSREStack(config, sre_name)
        self.postgres_provisioner = AzurePostgreSQLDatabase(
            sre_stack.output("remote_desktop")["connection_db_name"],
            sre_stack.secret("password-user-database-admin"),
            sre_stack.output("remote_desktop")["connection_db_server_name"],
            sre_stack.output("remote_desktop")["resource_group_name"],
            config.subscription_name,
        )
        self.users_: Sequence[ResearchUser] | None = None
        self.postgres_script_path: pathlib.Path = (
            pathlib.Path(__file__).parent.parent.parent / "resources" / "remote_desktop" / "postgresql"
        )
        self.sre_name = sre_name
        self.group_name = f"Data Safe Haven Users SRE {sre_name}"

    def list(self) -> Sequence[ResearchUser]:
        """List all Guacamole users"""
        if self.users_ is None:  # Allow for the possibility of an empty list of users
            postgres_output = self.postgres_provisioner.execute_scripts(
                [self.postgres_script_path / "list_users.mustache.sql"],
                mustache_values={"group_name": self.group_name},
            )
            # The output is of the form [
            #   ["sam_account_name1", "email_address1"],
            #   ["sam_account_name2", "email_address2"]
            # ]
            self.users_ = [
                ResearchUser(
                    sam_account_name=user_details[0].split("@")[0],
                    user_principal_name=user_details[0],
                    email_address=user_details[1],
                )
                for user_details in postgres_output
            ]
        return self.users_
