"""Backend for a Data Safe Haven environment"""
# Standard library imports
import pathlib
import requests
import time
from typing import Dict, Sequence

# Third party imports
from azure.core.polling import LROPoller
from azure.mgmt.rdbms.postgresql import PostgreSQLManagementClient
from azure.mgmt.rdbms.postgresql.operations import ServersOperations
from azure.mgmt.rdbms.postgresql.models import ServerUpdateParameters, FirewallRule
import psycopg2

# Local imports
from data_safe_haven.helpers import FileReader
from data_safe_haven.mixins import AzureMixin, LoggingMixin
from data_safe_haven.exceptions import (
    DataSafeHavenInputException,
    DataSafeHavenAzureException,
)


class PostgreSQLProvisioner(AzureMixin, LoggingMixin):
    """Provisioner for Azure PostgreSQL databases."""

    def __init__(
        self,
        config,
        resource_group_name,
        server_name,
        admin_password,
        database_name="guacamole",
    ):
        super().__init__(subscription_name=config.azure.subscription_name)
        self.cfg = config
        self.admin_password = admin_password
        self.current_ip = requests.get("https://api.ipify.org").content.decode("utf8")
        self.database_name = database_name
        self.db_client_ = None
        self.db_server_ = None
        self.resource_group_name = resource_group_name
        self.server_name = server_name

    @staticmethod
    def wait(poller: LROPoller) -> None:
        """Wait for a polling operation to finish."""
        while not poller.done():
            time.sleep(10)

    @property
    def db_client(self) -> PostgreSQLManagementClient:
        """Get the database client as a PostgreSQLManagementClient object."""
        if not self.db_client_:
            self.db_client_ = PostgreSQLManagementClient(
                self.credential, self.subscription_id
            )
        return self.db_client_

    @property
    def db_server(self) -> ServersOperations:
        """Get the database server as a ServersOperations object."""
        if not self.db_server_:
            self.db_server_ = self.db_client.servers.get(
                self.resource_group_name, self.server_name
            )
        return self.db_server_

    def db_connection(self, n_retries: int = 0) -> psycopg2._psycopg.connection:
        """Get the database connection as a ServersOperations object."""
        while True:
            try:
                connection = psycopg2.connect(
                    user=f"{self.db_server.administrator_login}@{self.server_name}",
                    password=self.admin_password,
                    host=self.db_server.fully_qualified_domain_name,
                    port="5432",
                    database=self.database_name,
                    sslmode="require",
                )
                break
            except psycopg2.OperationalError as exc:
                if n_retries > 0:
                    n_retries -= 1
                    time.sleep(10)
                else:
                    raise DataSafeHavenAzureException(
                        "Could not connect to database."
                    ) from exc
        return connection

    def load_sql(self, filepath: pathlib.Path, mustache_values: Dict = None) -> str:
        """Load filepath into a single SQL string."""
        reader = FileReader(filepath)
        # Strip any comment lines
        sql_lines = [
            line.split("--")[0]
            for line in reader.file_contents(mustache_values).split("\n")
        ]
        # Join into a single SQL string
        return " ".join([line for line in sql_lines if line])

    def execute_scripts(
        self, filepaths: Sequence[pathlib.Path], mustache_values: Dict = None
    ) -> Sequence[str]:
        """Execute scripts on the PostgreSQL server."""
        outputs = []
        connection = None

        try:
            # Add temporary firewall rule
            self.set_database_access("enabled")

            # Connect to the database and get a cursor to perform database operations
            connection = self.db_connection(n_retries=1)
            cursor = connection.cursor()

            # Apply the Guacamole initialisation script
            self.info("Running SQL scripts...", no_newline=True)
            for filepath in filepaths:
                commands = self.load_sql(filepath, mustache_values)
                cursor.execute(commands)
            if "SELECT" in cursor.statusmessage:
                outputs = [record for record in cursor]

            # Commit changes
            connection.commit()
            self.info("Finished running SQL scripts.", overwrite=True)

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
            self.set_database_access("disabled")
        return outputs

    def set_database_access(self, action: str) -> None:
        """Enable/disable database access to the PostgreSQL server."""
        rule_name = "AllowConfigurationUpdate"
        if action == "enabled":
            self.info(
                f"Adding temporary firewall rule for <fg=green>{self.current_ip}</>...",
                no_newline=True,
            )
            self.wait(
                self.db_client.servers.begin_update(
                    self.resource_group_name,
                    self.server_name,
                    ServerUpdateParameters(public_network_access="Enabled"),
                )
            )
            self.wait(
                self.db_client.firewall_rules.begin_create_or_update(
                    self.resource_group_name,
                    self.server_name,
                    rule_name,
                    FirewallRule(
                        start_ip_address=self.current_ip, end_ip_address=self.current_ip
                    ),
                )
            )
            self.db_connection(n_retries=5)
            self.info(
                f"Added temporary firewall rule for <fg=green>{self.current_ip}</>.",
                overwrite=True,
            )
        elif action == "disabled":
            self.info(
                f"Removing temporary firewall rule for <fg=green>{self.current_ip}</>...",
                no_newline=True,
            )
            self.wait(
                self.db_client.firewall_rules.begin_delete(
                    self.resource_group_name, self.server_name, rule_name
                )
            )
            self.wait(
                self.db_client.servers.begin_update(
                    self.resource_group_name,
                    self.server_name,
                    ServerUpdateParameters(public_network_access="Disabled"),
                )
            )
            self.info(
                f"Removed temporary firewall rule for <fg=green>{self.current_ip}</>.",
                overwrite=True,
            )
        else:
            raise DataSafeHavenInputException(
                f"Database access action {action} was not recognised."
            )
        self.info(
            f"Public network access to <fg=green>{self.server_name}</> is: {self.db_server.public_network_access}"
        )
