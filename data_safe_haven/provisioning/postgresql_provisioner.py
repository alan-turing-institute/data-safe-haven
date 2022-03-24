"""Backend for a Data Safe Haven environment"""
# Standard library imports
import requests
import time

# Third party imports
from azure.mgmt.rdbms.postgresql import PostgreSQLManagementClient
from azure.mgmt.rdbms.postgresql.models import ServerUpdateParameters, FirewallRule
import psycopg2

# Local imports
from data_safe_haven.mixins import AzureMixin, LoggingMixin
from data_safe_haven.exceptions import (
    DataSafeHavenInputException,
    DataSafeHavenAzureException,
)


class PostgreSQLProvisioner(AzureMixin, LoggingMixin):
    """Provisioner for Azure PostgreSQL databases."""

    def __init__(
        self, config, resources_path, resource_group_name, server_name, admin_password
    ):
        super().__init__(subscription_name=config.azure.subscription_name)
        self.cfg = config
        self.resources_path = resources_path
        self.resource_group_name = resource_group_name
        self.server_name = server_name
        self.admin_password = admin_password
        self.current_ip = requests.get("https://api.ipify.org").content.decode("utf8")

    @staticmethod
    def wait(poller):
        while not poller.done():
            time.sleep(10)

    def initialisation_commands(self):
        init_db_sql_path = (
            self.resources_path / "guacamole" / "postgresql" / "init_db.sql"
        )
        # Read file line-by-line removing comments
        with open(init_db_sql_path, "r") as f_sql:
            lines = [l.split("--")[0] for l in map(str.strip, f_sql.readlines())]
        # Join lines and return all commands
        return " ".join(lines)

    def set_database_access(self, db_client, action):
        rule_name = "AllowConfigurationUpdate"
        if action == "enabled":
            self.info(
                f"Adding temporary firewall rule for <fg=green>{self.current_ip}</>."
            )
            self.wait(
                db_client.servers.begin_update(
                    self.resource_group_name,
                    self.server_name,
                    ServerUpdateParameters(public_network_access="Enabled"),
                )
            )
            self.wait(
                db_client.firewall_rules.begin_create_or_update(
                    self.resource_group_name,
                    self.server_name,
                    rule_name,
                    FirewallRule(
                        start_ip_address=self.current_ip, end_ip_address=self.current_ip
                    ),
                )
            )
        elif action == "disabled":
            self.info(
                f"Removing temporary firewall rule for <fg=green>{self.current_ip}</>."
            )
            self.wait(
                db_client.firewall_rules.begin_delete(
                    self.resource_group_name, self.server_name, rule_name
                )
            )
            self.wait(
                db_client.servers.begin_update(
                    self.resource_group_name,
                    self.server_name,
                    ServerUpdateParameters(public_network_access="Disabled"),
                )
            )
        else:
            raise DataSafeHavenInputException(
                f"Database access action {action} was not recognised."
            )
        server = db_client.servers.get(self.resource_group_name, self.server_name)
        self.info(
            f"Public network access to <fg=green>{self.server_name}</> is: {server.public_network_access}"
        )

    def update(self):
        # Connect to Azure clients
        db_client = PostgreSQLManagementClient(self.credential, self.subscription_id)
        server = db_client.servers.get(self.resource_group_name, self.server_name)
        connection = None

        # Add temporary firewall rule
        self.set_database_access(db_client, "enabled")

        try:
            # Connect to the database
            connection = psycopg2.connect(
                user=f"{server.administrator_login}@{self.server_name}",
                password=self.admin_password,
                host=server.fully_qualified_domain_name,
                port="5432",
                database="guacamole",
                sslmode="require",
            )
            # Create a cursor to perform database operations
            cursor = connection.cursor()

            # Apply the Guacamole initialisation script
            self.info("Initialising required Guacamole configuration.")
            commands = self.initialisation_commands()
            cursor.execute(commands)

            # Commit changes
            connection.commit()
            self.info("Finished configuring Guacamole.")

        except (Exception, psycopg2.Error) as exc:
            raise DataSafeHavenAzureException(
                f"Error while connecting to PostgreSQL: {exc}"
            ) from exc
        finally:
            # Close the connection if it is open
            if connection:
                cursor.close()
                connection.close()
            # Remove temporary firewall rules
            self.set_database_access(db_client, "disabled")
