# Standard library imports
import pathlib
import tempfile
from typing import Any, Sequence

# Local imports
from data_safe_haven.configuration.components import PostgreSQLProvisioner
from data_safe_haven.exceptions import DataSafeHavenInputException
from data_safe_haven.helpers import FileReader
from data_safe_haven.mixins import LoggingMixin
from .research_user import ResearchUser
from data_safe_haven.config import Config


class GuacamoleUsers(LoggingMixin):
    def __init__(self, config: Config, sre_name: str, *args: Any, **kwargs: Any):
        super().__init__(*args, **kwargs)
        self.postgres_provisioner = PostgreSQLProvisioner(
            config.sre[sre_name].remote_desktop.connection_db_name,
            config.get_secret(
                config.sre[sre_name].remote_desktop[
                    "connection_db_server_admin_password_secret"
                ]
            ),
            config.sre[sre_name].remote_desktop.connection_db_server_name,
            config.sre[sre_name].remote_desktop.resource_group_name,
            config.subscription_name,
        )

        self.users_ = None
        self.postgres_script_path = (
            pathlib.Path(__file__).parent.parent.parent
            / "resources"
            / "remote_desktop"
            / "postgresql"
        )

    def list(self) -> Sequence[ResearchUser]:
        if self.users_ is None:  # Allow for the possibility of an empty list of users
            postgres_output = self.postgres_provisioner.execute_scripts(
                [self.postgres_script_path / "list_users.sql"]
            )
            self.users_ = [
                ResearchUser(
                    sam_account_name=tokens[0].split("@")[0],
                    user_principal_name=tokens[0],
                    email_address=tokens[2],
                )
                for tokens in postgres_output
            ]
        return self.users_

    def add(self, users: Sequence[ResearchUser]) -> None:
        """Add list of users to Guacamole"""
        # Update Guacamole users
        users_to_add = []
        for new_user in users:
            if new_user in self.users:
                self.debug(
                    f"User '{new_user.preferred_username}' already exists in Guacamole"
                )
            else:
                self.info(f"Adding '{new_user.preferred_username}' to Guacamole")
                users_to_add.append(new_user)

        # Add user details to the mustache template
        user_data = {
            "users": [
                {
                    "username": user.user_principal_name,
                    "full_name": user.display_name,
                    "password_hash": user.password_hash,
                    "password_salt": user.password_salt,
                    "password_date": user.password_date.isoformat(),
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
            self.info(f"Removing '{user.preferred_username}' from Guacamole")

        # Create a temporary file with user details and run it on the Guacamole database
        sql_file_name = None
        try:
            with tempfile.NamedTemporaryFile("w", delete=False) as f_tmp:
                f_tmp.writelines(reader.file_contents(user_data))
                sql_file_name = f_tmp.name
            self.postgres_provisioner.execute_scripts([sql_file_name])
            self.users_ = [user for user in self.users_ if user not in users]
        except Exception as exc:
            raise DataSafeHavenInputException(
                f"Could not update database users.\n{str(exc)}"
            ) from exc
        finally:
            if sql_file_name:
                pathlib.Path(sql_file_name).unlink()

    def set(self, users: Sequence[ResearchUser]) -> None:
        """Set Guacamole users to specified list"""
        users_to_remove = [user for user in self.users if user not in users]
        self.remove(users_to_remove)
        users_to_add = [user for user in users if user not in self.users]
        self.add(users_to_add)
