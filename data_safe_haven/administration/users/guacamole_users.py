# Standard library imports
import pathlib
import tempfile
from typing import Sequence

# Local imports
from data_safe_haven.exceptions import DataSafeHavenInputException
from data_safe_haven.helpers import FileReader
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.provisioning import PostgreSQLProvisioner
from .research_user import ResearchUser


class GuacamoleUsers(LoggingMixin):
    def __init__(self, config, postgresql_password, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.cfg = config
        self.postgres_provisioner = PostgreSQLProvisioner(
            self.cfg,
            self.cfg.pulumi.outputs.guacamole.resource_group_name,
            self.cfg.pulumi.outputs.guacamole.postgresql_server_name,
            postgresql_password,
        )
        self.users_ = []
        self.postgres_script_path = (
            pathlib.Path(__file__).parent.parent.parent
            / "resources"
            / "guacamole"
            / "postgresql"
        )

    @property
    def users(self) -> Sequence[ResearchUser]:
        if not self.users_:
            postgres_output = self.postgres_provisioner.execute_scripts(
                [self.postgres_script_path / "list_users.sql"]
            )
            self.users_ = [
                ResearchUser(
                    username=result[0].split("@")[0],
                    user_principal_name=result[0],
                    password_salt=result[1],
                    password_hash=result[2],
                    password_date=result[3],
                )
                for result in postgres_output
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
            raise DataSafeHavenInputException(exc)
        finally:
            if sql_file_name:
                pathlib.Path(sql_file_name).unlink()

    def set(self, users: Sequence[ResearchUser]) -> None:
        """Set Guacamole users to specified list"""
        users_to_remove = [user for user in self.users if user not in users]
        self.remove(users_to_remove)
        users_to_add = [user for user in users if user not in self.users]
        self.add(users_to_add)
