"""Backend for a Data Safe Haven environment"""
# Standard library imports
import pathlib
import time
from datetime import datetime
from typing import Dict, Sequence

# Third party imports
import psycopg2
import requests
from azure.core.polling import LROPoller
from azure.mgmt.rdbms.postgresql import PostgreSQLManagementClient
from azure.mgmt.rdbms.postgresql.models import FirewallRule, ServerUpdateParameters
from azure.mgmt.rdbms.postgresql.operations import ServersOperations

# Local imports
from data_safe_haven.exceptions import (
    DataSafeHavenAzureException,
    DataSafeHavenInputException,
)
from data_safe_haven.helpers import FileReader
from data_safe_haven.mixins import AzureMixin, LoggingMixin


class AzurePostgreSQLDatabase(AzureMixin, LoggingMixin):
    """Interface for Azure PostgreSQL databases."""

    def __init__(
        self,
        database_name,
        database_server_admin_password,
        database_server_name,
        resource_group_name,
        subscription_name,
    ):
        super().__init__(subscription_name=subscription_name)
        self.current_ip = requests.get("https://api.ipify.org").content.decode("utf8")
        self.db_client_ = None
        self.db_name = database_name
        self.db_server_ = None
        self.db_server_admin_password = database_server_admin_password
        self.resource_group_name = resource_group_name
        self.server_name = database_server_name
        self.rule_suffix = datetime.now().strftime(r"%Y%m%d-%H%M%S")

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
                    password=self.db_server_admin_password,
                    host=self.db_server.fully_qualified_domain_name,
                    port="5432",
                    database=self.db_name,
                    sslmode="require",
                )
                break
            except psycopg2.OperationalError as exc:
                if n_retries > 0:
                    n_retries -= 1
                    time.sleep(10)
                else:
                    raise DataSafeHavenAzureException(
                        f"Could not connect to database.\n{str(exc)}"
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
            for filepath in filepaths:
                self.info(f"Running SQL script: <fg=green>{filepath.name}</>.")
                commands = self.load_sql(filepath, mustache_values)
                cursor.execute(commands)
                if "SELECT" in cursor.statusmessage:
                    outputs += [record for record in cursor]

            # Commit changes
            connection.commit()
            self.info(f"Finished running {len(filepaths)} SQL scripts.")
        except (Exception, psycopg2.Error) as exc:
            raise DataSafeHavenAzureException(
                f"Error while connecting to PostgreSQL.\n{str(exc)}"
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
        rule_name = f"AllowConfigurationUpdate-{self.rule_suffix}"

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
        self.db_server_ = None  # Force refresh of self.db_server
        self.info(
            f"Public network access to <fg=green>{self.server_name}</> is <fg=green>{self.db_server.public_network_access}</>."
        )
