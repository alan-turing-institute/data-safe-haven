import pathlib
from collections.abc import Sequence

from data_safe_haven.config import Context, DSHPulumiConfig, SREConfig
from data_safe_haven.external import AzurePostgreSQLDatabase, AzureSdk
from data_safe_haven.infrastructure import SREProjectManager

from .research_user import ResearchUser


class GuacamoleUsers:
    """Interact with users in a Guacamole database."""

    def __init__(
        self,
        context: Context,
        config: SREConfig,
        pulumi_config: DSHPulumiConfig,
    ):
        sre_stack = SREProjectManager(
            context=context,
            config=config,
            pulumi_config=pulumi_config,
        )
        # Read the SRE database secret from key vault
        azure_sdk = AzureSdk(subscription_name=context.subscription_name)
        sre_subscription_name = azure_sdk.get_subscription_name(
            config.azure.subscription_id
        )
        connection_db_server_password = azure_sdk.get_keyvault_secret(
            sre_stack.output("data")["key_vault_name"],
            sre_stack.output("data")["password_user_database_admin_secret"],
        )
        self.postgres_provisioner = AzurePostgreSQLDatabase(
            sre_stack.output("remote_desktop")["connection_db_name"],
            connection_db_server_password,
            sre_stack.output("remote_desktop")["connection_db_server_name"],
            sre_stack.output("remote_desktop")["resource_group_name"],
            sre_subscription_name,
        )
        self.users_: Sequence[ResearchUser] | None = None
        self.postgres_script_path: pathlib.Path = (
            pathlib.Path(__file__).parent.parent.parent
            / "resources"
            / "remote_desktop"
            / "postgresql"
        )
        self.group_name = f"Data Safe Haven SRE {config.name} Users"

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
