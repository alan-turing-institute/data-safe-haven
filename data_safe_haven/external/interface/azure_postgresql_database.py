"""Backend for a Data Safe Haven environment"""
# Standard library imports
import pathlib
import time
from collections.abc import Sequence
from datetime import datetime
from typing import Any

# Third party imports
import psycopg2
import requests
from azure.core.polling import LROPoller
from azure.mgmt.rdbms.postgresql import PostgreSQLManagementClient
from azure.mgmt.rdbms.postgresql.models import (
    FirewallRule,
    Server,
    ServerUpdateParameters,
)

# Local imports
from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenInputError,
)
from data_safe_haven.external import AzureApi
from data_safe_haven.utility import FileReader, Logger, PathType


class AzurePostgreSQLDatabase:
    """Interface for Azure PostgreSQL databases."""

    current_ip: str
    db_client_: PostgreSQLManagementClient | None
    db_name: str
    db_server_: Server | None
    db_server_admin_password: str
    resource_group_name: str
    server_name: str
    rule_suffix: str

    def __init__(
        self,
        database_name: str,
        database_server_admin_password: str,
        database_server_name: str,
        resource_group_name: str,
        subscription_name: str,
    ) -> None:
        self.azure_api = AzureApi(subscription_name)
        self.current_ip = requests.get("https://api.ipify.org", timeout=300).content.decode("utf8")
        self.db_client_ = None
        self.db_name = database_name
        self.db_server_ = None
        self.db_server_admin_password = database_server_admin_password
        self.logger = Logger()
        self.resource_group_name = resource_group_name
        self.server_name = database_server_name
        self.rule_suffix = datetime.now(tz=datetime.timezone.utc).strftime(r"%Y%m%d-%H%M%S")

    @staticmethod
    def wait(poller: LROPoller[Any]) -> None:
        """Wait for a polling operation to finish."""
        while not poller.done():
            time.sleep(10)

    @property
    def db_client(self) -> PostgreSQLManagementClient:
        """Get the database client."""
        if not self.db_client_:
            self.db_client_ = PostgreSQLManagementClient(self.azure_api.credential, self.azure_api.subscription_id)
        return self.db_client_

    @property
    def db_server(self) -> Server:
        """Get the database server."""
        if not self.db_server_:
            self.db_server_ = self.db_client.servers.get(self.resource_group_name, self.server_name)
        return self.db_server_

    def db_connection(self, n_retries: int = 0) -> psycopg2.extensions.connection:
        """Get the database connection."""
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
                    msg = f"Could not connect to database.\n{exc}"
                    raise DataSafeHavenAzureError(msg) from exc
        return connection

    def load_sql(self, filepath: PathType, mustache_values: dict[str, str] | None = None) -> str:
        """Load filepath into a single SQL string."""
        reader = FileReader(filepath)
        # Strip any comment lines
        sql_lines = [line.split("--")[0] for line in reader.file_contents(mustache_values).split("\n")]
        # Join into a single SQL string
        return " ".join([line for line in sql_lines if line])

    def execute_scripts(
        self,
        filepaths: Sequence[PathType],
        mustache_values: dict[str, Any] | None = None,
    ) -> list[list[str]]:
        """Execute scripts on the PostgreSQL server."""
        outputs: list[list[str]] = []
        connection: psycopg2.extensions.connection | None = None
        cursor = None

        try:
            # Add temporary firewall rule
            self.set_database_access("enabled")

            # Connect to the database and get a cursor to perform database operations
            connection = self.db_connection(n_retries=1)
            cursor = connection.cursor()

            # Apply the Guacamole initialisation script
            for filepath in filepaths:
                _filepath = pathlib.Path(filepath)
                self.logger.info(f"Running SQL script: [green]{_filepath.name}[/].")
                commands = self.load_sql(_filepath, mustache_values)
                cursor.execute(commands)
                if "SELECT" in cursor.statusmessage:
                    outputs += [[str(msg) for msg in msg_tuple] for msg_tuple in cursor]

            # Commit changes
            connection.commit()
            self.logger.info(f"Finished running {len(filepaths)} SQL scripts.")
        except (Exception, psycopg2.Error) as exc:
            msg = f"Error while connecting to PostgreSQL.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc
        finally:
            # Close the connection if it is open
            if connection:
                if cursor:
                    cursor.close()  # type: ignore
                connection.close()
            # Remove temporary firewall rules
            self.set_database_access("disabled")
        return outputs

    def set_database_access(self, action: str) -> None:
        """Enable/disable database access to the PostgreSQL server."""
        rule_name = f"AllowConfigurationUpdate-{self.rule_suffix}"

        if action == "enabled":
            self.logger.debug(
                f"Adding temporary firewall rule for [green]{self.current_ip}[/]...",
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
                    FirewallRule(start_ip_address=self.current_ip, end_ip_address=self.current_ip),
                )
            )
            self.db_connection(n_retries=5)
            self.logger.info(
                f"Added temporary firewall rule for [green]{self.current_ip}[/].",
            )
        elif action == "disabled":
            self.logger.debug(
                f"Removing temporary firewall rule for [green]{self.current_ip}[/]...",
            )
            self.wait(self.db_client.firewall_rules.begin_delete(self.resource_group_name, self.server_name, rule_name))
            self.wait(
                self.db_client.servers.begin_update(
                    self.resource_group_name,
                    self.server_name,
                    ServerUpdateParameters(public_network_access="Disabled"),
                )
            )
            self.logger.info(
                f"Removed temporary firewall rule for [green]{self.current_ip}[/].",
            )
        else:
            msg = f"Database access action {action} was not recognised."
            raise DataSafeHavenInputError(msg)
        self.db_server_ = None  # Force refresh of self.db_server
        self.logger.info(
            f"Public network access to [green]{self.server_name}[/]"
            f" is [green]{self.db_server.public_network_access}[/]."
        )
