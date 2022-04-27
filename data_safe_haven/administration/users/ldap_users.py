# Standard library imports
from typing import Sequence

# Local imports
from data_safe_haven.helpers import AzureFileShareHelper, password
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.provisioning import ContainerProvisioner
from .research_user import ResearchUser


class LdapUsers(LoggingMixin):
    def __init__(self, config, *args, **kwargs):
        super().__init__(*args, **kwargs)
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
        self.users_ = []

    @property
    def users(self) -> Sequence[ResearchUser]:
        if not self.users_:
            ldap_user_list = self.ldap_container_group.run_executable(
                f"{self.cfg.pulumi.outputs.authentication.container_group_name}-openldap",
                "/opt/commands/list_users.sh",
            )
            all_users = [
                ResearchUser.from_ldap(user_string) for user_string in ldap_user_list
            ]
            self.users_ = [user for user in all_users if user.is_researcher]
        return self.users_

    def add(self, users: Sequence[ResearchUser]) -> None:
        """Add list of users to LDAP"""
        ldap_users_to_add = []
        for new_user in users:
            if new_user in self.users:
                self.debug(f"User '{new_user.username}' already exists in LDAP")
                existing_user = self.users[self.users.index(new_user)]
                if existing_user.account_status == "disabled":
                    self.info(
                        f"Enabling previously disabled user '{existing_user.username}' in LDAP"
                    )
                existing_user.account_status = "enabled"
            else:
                self.info(f"Adding '{new_user.username}' to LDAP")
                ldap_users_to_add.append(new_user)
        if ldap_users_to_add:
            self.set(self.users + ldap_users_to_add)

    def next_uid(self) -> int:
        """Get the next unused UID at or above 30000"""
        return max(
            [30000]
            + [
                (int(user.uid_number) + 1 if user.uid_number else 0)
                for user in self.users
            ]
        )

    def remove(self, users: Sequence[ResearchUser]) -> None:
        """Remove list of users from LDAP"""
        update_needed = False
        for user in self.users:
            if user in users:
                if user.account_status != "disabled":
                    self.info(f"Disabling '{user.username}' in LDAP")
                    user.account_status = "disabled"
                    update_needed = True
        if update_needed:
            self.set(self.users)

    def set(self, users: Sequence[ResearchUser]) -> None:
        """Set LDAP users to specified list"""
        # Write one entry for each user
        ldif_lines = []
        for user in users:
            if not user.uid_number:
                user.uid_number = self.next_uid()
        for user in sorted(users, key=lambda user: user.uid_number):
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
            ldif_lines.append("")  # blank line needed to separate LDIF statements

        # Upload to the container
        self.ldap_file_share_ldifs.upload(
            "03_research_users.ldif", "\n".join(ldif_lines)
        )

        # Write members of the researchers group
        ldif_lines = []
        group_members = sorted(
            [user for user in users if user.account_status == "enabled"],
            key=lambda user: user.uid_number,
        )
        if group_members:
            ldif_lines.append(f"dn: cn=researchers,{self.cfg.ldap_group_base_dn}")
            ldif_lines.append("changetype: modify")
            ldif_lines.append("add: memberUid")
            for user in group_members:
                ldif_lines.append(f"memberUid: {user.username}")

        # Upload to the container and restart it
        self.ldap_file_share_ldifs.upload(
            "04_research_group_members.ldif", "\n".join(ldif_lines)
        )
        self.ldap_container_group.restart()
        self.users_ = users
