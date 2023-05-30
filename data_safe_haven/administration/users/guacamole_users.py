# Standard library imports
import pathlib
import tempfile
from datetime import datetime, timezone
from typing import Any, Optional, Sequence

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenInputException
from data_safe_haven.external.interface import AzurePostgreSQLDatabase
from data_safe_haven.helpers import FileReader, hex_string
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.pulumi import PulumiStack
from .research_user import ResearchUser


class GuacamoleUsers(LoggingMixin):
    def __init__(self, config: Config, sre_name: str, *args: Any, **kwargs: Any):
        super().__init__(*args, **kwargs)
        sre_stack = PulumiStack(config, "SRE", sre_name=sre_name)
        self.postgres_provisioner = AzurePostgreSQLDatabase(
            sre_stack.output("remote_desktop")["connection_db_name"],
            sre_stack.secret("password-user-database-admin"),
            sre_stack.output("remote_desktop")["connection_db_server_name"],
            sre_stack.output("remote_desktop")["resource_group_name"],
            config.subscription_name,
        )
        self.users_: Optional[Sequence[ResearchUser]] = None
        self.postgres_script_path: pathlib.Path = (
            pathlib.Path(__file__).parent.parent.parent
            / "resources"
            / "remote_desktop"
            / "postgresql"
        )
        self.sre_name = sre_name

    def add(self, users: Sequence[ResearchUser]) -> None:
        """Add sequence of users to Guacamole"""
        # Update Guacamole users
        users_to_add = []
        for new_user in users:
            if new_user in self.list():
                self.debug(
                    f"User '<options=bold>{new_user.preferred_username}</>' already exists in SRE '<options=bold>{self.sre_name}</>' database"
                )
            else:
                self.info(
                    f"Adding '<options=bold>{new_user.preferred_username}</>' to SRE '<options=bold>{self.sre_name}</>' database"
                )
                users_to_add.append(new_user)

        # Add user details to the mustache template
        pwd_date = datetime.utcnow().replace(tzinfo=timezone.utc).isoformat()
        user_data = {
            "users": [
                {
                    "username": user.user_principal_name,
                    "email_address": user.email_address,
                    "full_name": user.display_name,
                    "password_hash": hex_string(64),
                    "password_salt": hex_string(64),
                    "password_date": pwd_date,
                }
                for user in users_to_add
            ],
            "group_name": "Research Users",
        }
        if user_data:
            self.postgres_provisioner.execute_scripts(
                [self.postgres_script_path / "add_users.mustache.sql"],
                mustache_values=user_data,
            )

    def list(self) -> Sequence[ResearchUser]:
        """List all Guacamole users"""
        if self.users_ is None:  # Allow for the possibility of an empty list of users
            postgres_output = self.postgres_provisioner.execute_scripts(
                [self.postgres_script_path / "list_users.sql"]
            )
            # The output is of the form [["sam_account_name1", "email_address1"], ["sam_account_name2", "email_address2"]]
            self.users_ = [
                ResearchUser(
                    sam_account_name=user_details[0].split("@")[0],
                    user_principal_name=user_details[0],
                    email_address=user_details[1],
                )
                for user_details in postgres_output
            ]
        return self.users_

    def remove(self, users: Sequence[ResearchUser]) -> None:
        """Remove list of users from Guacamole"""
        if not users:
            return
        # Add user details to the mustache template
        reader = FileReader(self.postgres_script_path / "remove_users.mustache.sql")
        user_data = {
            "users": [
                {
                    "username": user.user_principal_name,
                }
                for user in users
            ]
        }
        for user in users:
            self.info(
                f"Removing '{user.preferred_username}' from SRE '{self.sre_name}' database"
            )

        # Create a temporary file with user details and run it on the Guacamole database
        sql_file_name: Optional[pathlib.Path] = None
        try:
            with tempfile.NamedTemporaryFile("w", delete=False) as f_tmp:
                f_tmp.writelines(reader.file_contents(user_data))
                sql_file_name = pathlib.Path(f_tmp.name)
            self.postgres_provisioner.execute_scripts([sql_file_name])
            if self.users_:
                self.users_ = [user for user in self.users_ if user not in users]
        except Exception as exc:
            raise DataSafeHavenInputException(
                f"Could not update SRE '{self.sre_name}' database users.\n{str(exc)}"
            ) from exc
        finally:
            if sql_file_name:
                pathlib.Path(sql_file_name).unlink()

    def set(self, users: Sequence[ResearchUser]) -> None:
        """Set Guacamole users to specified list"""
        users_to_remove = [user for user in self.list() if user not in users]
        self.remove(users_to_remove)
        users_to_add = [user for user in users if user not in self.list()]
        self.add(users_to_add)
