# Standard library imports
import pathlib

# Local imports
from data_safe_haven.mixins import AzureMixin, LoggingMixin
from data_safe_haven.provisioning import ContainerProvisioner, PostgreSQLProvisioner


class Users(LoggingMixin, AzureMixin):
    def __init__(self, config, *args, **kwargs):
        super().__init__(
            subscription_name=config.azure.subscription_name, *args, **kwargs
        )
        self.cfg = config

    def list(self, postgresql_password):
        ldap_container_group = ContainerProvisioner(
            self.cfg,
            self.cfg.pulumi.outputs.authentication.resource_group_name,
            self.cfg.pulumi.outputs.authentication.container_group_name,
        )

        ldap_users = ldap_container_group.run_executable(
            f"container-{self.cfg.environment_name}-authentication-openldap",
            "/opt/commands/list_users.sh",
        )

        postgres_provisioner = PostgreSQLProvisioner(
            self.cfg,
            self.cfg.pulumi.outputs.guacamole.resource_group_name,
            self.cfg.pulumi.outputs.guacamole.postgresql_server_name,
            postgresql_password,
        )
        postgres_output = postgres_provisioner.execute_scripts(
            [
                pathlib.Path(__file__).parent.parent
                / "resources"
                / "guacamole"
                / "postgresql"
                / "list_users.sql"
            ]
        )
        postgres_users = [result[0] for result in postgres_output]

        # Print list of users
        user_data = []
        for username in sorted(set(ldap_users + postgres_users)):
            user_data.append(
                [
                    username,
                    "x" if username in ldap_users else "",
                    "x" if username in postgres_users else "",
                ]
            )
        user_headers = ["username", "In LDAP", "In PostgreSQL"]
        for line in self.tabulate(user_headers, user_data):
            self.info(line)
