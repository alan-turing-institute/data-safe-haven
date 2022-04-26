# Standard library imports
import contextlib
import csv
import datetime
import pathlib
import tempfile

# Local imports
from data_safe_haven.exceptions import DataSafeHavenInputException
from data_safe_haven.helpers import AzureFileShareHelper, FileReader, hex_string, password
from data_safe_haven.mixins import AzureMixin, LoggingMixin
from data_safe_haven.provisioning import ContainerProvisioner, PostgreSQLProvisioner


class ResearchUser:
    def __init__(self, account_status=None, email_address=None, first_name=None, is_researcher=False, last_name=None, phone_number=None, uid_number=None, username=None, password_hash=None, password_salt=None, password_date=None):
        self.account_status = account_status
        self.email_address = email_address
        self.first_name = first_name
        self.is_researcher = is_researcher
        self.last_name = last_name
        self.phone_number = phone_number
        self.uid_number = int(uid_number) if uid_number else None
        self.username_ = username
        self.password_hash = password_hash if password_hash else hex_string(64)
        self.password_salt = password_salt if password_hash else hex_string(64)
        self.password_date = password_date if password_date else datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc)

    @classmethod
    def from_ldap(cls, ldap_string):
        kwargs = {}
        for item in ldap_string.split(";"):
            with contextlib.suppress(ValueError):
                field, value = item.split(":")
                if field == "employeeType":
                    kwargs["account_status"] = value
                elif field == "givenName":
                    kwargs["first_name"] = value
                elif field == "isResearcher":
                    kwargs["is_researcher"] = (value == "1")
                elif field == "mail":
                    kwargs["email_address"] = value
                elif field == "mobile":
                    kwargs["phone_number"] = value
                elif field == "uid":
                    kwargs["username"] = value
                elif field == "uidNumber":
                    kwargs["uid_number"] = value
                elif field == "sn":
                    kwargs["last_name"] = value
        return cls(**kwargs)

    @classmethod
    def from_csv(cls, **kwargs):
        return cls(**kwargs)

    @property
    def username(self):
        if self.username_:
            return self.username_
        return f"{self.first_name}.{self.last_name}".lower()

    def __eq__(self, other):
        if isinstance(other, ResearchUser):
            return (self.username == other.username)
        return False

    def __str__(self):
        return f"{self.first_name} {self.last_name} '{self.username}' (UID: {self.uid_number}). Email {self.email_address}, phone {self.phone_number}, status '{self.account_status}'"


class Users(LoggingMixin, AzureMixin):
    def __init__(self, config, postgresql_password, *args, **kwargs):
        super().__init__(
            subscription_name=config.azure.subscription_name, *args, **kwargs
        )
        self.cfg = config
        self.ldap_container_group = ContainerProvisioner(
            self.cfg,
            self.cfg.pulumi.outputs.authentication.resource_group_name,
            self.cfg.pulumi.outputs.authentication.container_group_name,
        )
        self.ldap_file_share_ldifs = AzureFileShareHelper(
            self.cfg,
            self.cfg.pulumi.outputs.state.storage_account_name,
            self.cfg.pulumi.outputs.state.resource_group_name,
            self.cfg.pulumi.outputs.authentication.file_share_name_ldifs,
        )
        self.postgres_provisioner = PostgreSQLProvisioner(
            self.cfg,
            self.cfg.pulumi.outputs.guacamole.resource_group_name,
            self.cfg.pulumi.outputs.guacamole.postgresql_server_name,
            postgresql_password,
        )
        self.ldap_users_ = []
        self.guacamole_users_ = []

    @property
    def ldap_users(self) -> list[ResearchUser]:
        if not self.ldap_users_:
            ldap_user_list = self.ldap_container_group.run_executable(
                f"{self.cfg.pulumi.outputs.authentication.container_group_name}-openldap",
                "/opt/commands/list_users.sh",
            )
            all_users = [ResearchUser.from_ldap(user_string) for user_string in ldap_user_list]
            self.ldap_users_ = [user for user in all_users if user.is_researcher]
        return self.ldap_users_

    @property
    def guacamole_users(self) -> list[ResearchUser]:
        if not self.guacamole_users_:
            postgres_output = self.postgres_provisioner.execute_scripts(
                [
                    pathlib.Path(__file__).parent.parent
                    / "resources"
                    / "guacamole"
                    / "postgresql"
                    / "list_users.sql"
                ]
            )
            self.guacamole_users_ = [ResearchUser(username=result[0], password_salt=result[1], password_hash=result[2], password_date=result[3]) for result in postgres_output]
        return self.guacamole_users_

    def add(self, users_csv):
        with open(users_csv) as f_csv:
            new_users = [ResearchUser.from_csv(account_status="enabled", **user) for user in csv.DictReader(f_csv, delimiter=";")]
        for new_user in new_users:
            self.debug(f"Processing new user: {str(new_user)}")

        # Update self.ldap_users and self.guacamole users with new users
        for new_user in new_users:
            # Update LDAP users
            if new_user in self.ldap_users:
                self.debug(f"User {new_user} already exists in LDAP")
                # TODO handle disabled users here
            else:
                new_user.uid_number = self.next_ldap_uid()
                self.info(f"Adding {new_user} to LDAP")
                self.ldap_users_.append(new_user)

            # Update Guacamole users
            if new_user in self.guacamole_users:
                self.debug(f"User {new_user} already exists in Guacamole")
            else:
                self.info(f"Adding {new_user} to Guacamole")
                self.guacamole_users_.append(new_user)

        # Commit changes
        self.set_ldap_users()
        self.set_guacamole_users()

    def list(self):
        """List LDAP and Guacamole users"""
        user_data = []
        ldap_usernames = [user.username for user in self.ldap_users]
        guacamole_usernames = [user.username for user in self.guacamole_users]
        for username in sorted(set(ldap_usernames + guacamole_usernames)):
            user_data.append(
                [
                    username,
                    "x" if username in ldap_usernames else "",
                    "x" if username in guacamole_usernames else "",
                ]
            )
        user_headers = ["username", "In LDAP", "In Guacamole"]
        for line in self.tabulate(user_headers, user_data):
            self.info(line)

    def next_ldap_uid(self):
       """Get the next unused UID at or above 30000"""
       return max([30000] + [(int(user.uid_number) + 1 if user.uid_number else 0) for user in self.ldap_users])

    def set_ldap_users(self):
        # Write one entry for each user
        ldif_lines = []
        for user in sorted(self.ldap_users, key=lambda user: user.uid_number):
            ldif_lines.append(f"dn: uid={user.username},{self.cfg.ldap_user_base_dn}")
            ldif_lines.append(f"givenName: {user.first_name}")
            ldif_lines.append(f"sn: {user.last_name}")
            ldif_lines.append(f"cn: {user.first_name} {user.last_name}")
            ldif_lines.append(f"uid: {user.username}")
            ldif_lines.append("objectClass: inetOrgPerson")
            ldif_lines.append("objectClass: posixAccount")
            ldif_lines.append("objectClass: top")
            ldif_lines.append(f"userPassword: {password(20)}")
            ldif_lines.append(f"uidNumber: {user.uid_number}")
            ldif_lines.append("gidNumber: 10000")
            ldif_lines.append(f"homeDirectory: /home/{user.username}")
            ldif_lines.append(f"mail: {user.email_address}")
            ldif_lines.append(f"mobile: {user.phone_number}")
            ldif_lines.append(f"employeeType: {user.account_status}")
            ldif_lines.append("") # blank line needed to separate LDIF statements

        # Upload to the container
        self.ldap_file_share_ldifs.upload("03_research_users.ldif", "\n".join(ldif_lines))

        # Write members of the researchers group
        ldif_lines = []
        group_members = sorted([user for user in self.ldap_users if user.account_status == "enabled"], key=lambda user: user.uid_number)
        if group_members:
            ldif_lines.append(f"dn: cn=researchers,{self.cfg.ldap_group_base_dn}")
            ldif_lines.append("changetype: modify")
            ldif_lines.append("add: memberUid")
            for user in group_members:
                ldif_lines.append(f"memberUid: {user.username}")

        # Upload to the container and restart it
        self.ldap_file_share_ldifs.upload("04_research_group_members.ldif", "\n".join(ldif_lines))
        self.ldap_container_group.restart()

    def set_guacamole_users(self):
        self.add_guacamole_users(self.guacamole_users)

    def add_guacamole_users(self, users):
        # Add user details to the mustache template
        reader = FileReader(
            pathlib.Path(__file__).parent.parent
             / "resources"
             / "guacamole"
             / "postgresql"
             / "add_users.mustache.sql"
        )
        user_data = {"users": [
            {
                "username": user.username,
                "password_hash": user.password_hash,
                "password_salt": user.password_salt,
                "password_date": user.password_date.isoformat()
            }
            for user in users
        ]}

        # Create a temporary file with user details and run it on the Guacamole database
        sql_file_name = None
        try:
            with tempfile.NamedTemporaryFile("w", delete=False) as f_tmp:
                f_tmp.writelines(reader.file_contents(user_data))
                sql_file_name = f_tmp.name
            self.postgres_provisioner.execute_scripts([sql_file_name])
        except Exception as exc:
            raise DataSafeHavenInputException(exc)
        finally:
            if sql_file_name:
                pathlib.Path(sql_file_name).unlink()
