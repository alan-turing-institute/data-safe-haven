import datetime
import pathlib
import time
from collections.abc import Sequence
from typing import Any, cast

import psycopg
import requests
from azure.core.polling import LROPoller
from azure.mgmt.rdbms.postgresql_flexibleservers import PostgreSQLManagementClient
from azure.mgmt.rdbms.postgresql_flexibleservers.models import (
    FirewallRule,
    Server,
)

from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenInputError,
)
from data_safe_haven.external import AzureApi
from data_safe_haven.utility import FileReader, LoggingSingleton, PathType


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
        self.current_ip = requests.get(
            "https://api.ipify.org", timeout=300
        ).content.decode("utf8")
        self.db_client_ = None
        self.db_name = database_name
        self.db_server_ = None
        self.db_server_admin_password = database_server_admin_password
        self.logger = LoggingSingleton()
        self.port = 5432
        self.resource_group_name = resource_group_name
        self.server_name = database_server_name
        self.rule_suffix = datetime.datetime.now(tz=datetime.UTC).strftime(
            r"%Y%m%d-%H%M%S"
        )

    @staticmethod
    def wait(poller: LROPoller[Any]) -> None:
        """Wait for a polling operation to finish."""
        while not poller.done():
            time.sleep(10)

    @property
    def connection_string(self) -> str:
        return " ".join(
            [
                f"dbname={self.db_name}",
                f"host={self.db_server.fully_qualified_domain_name}",
                f"password={self.db_server_admin_password}",
                f"port={self.port}",
                f"user={self.db_server.administrator_login}",
                "sslmode=require",
            ]
        )

    @property
    def db_client(self) -> PostgreSQLManagementClient:
        """Get the database client."""
        if not self.db_client_:
            self.db_client_ = PostgreSQLManagementClient(
                self.azure_api.credential, self.azure_api.subscription_id
            )
        return self.db_client_

    @property
    def db_server(self) -> Server:
        """Get the database server."""
        # self.logger.debug(f"Connecting to database using {self.connection_string}")
        if not self.db_server_:
            self.db_server_ = self.db_client.servers.get(
                self.resource_group_name, self.server_name
            )
        return self.db_server_

    def db_connection(self, n_retries: int = 0) -> psycopg.Connection:
        """Get the database connection."""
        while True:
            try:
                try:
                    connection = psycopg.connect(self.connection_string)
                    break
                except psycopg.OperationalError as exc:
                    if n_retries <= 0:
                        raise exc
                    n_retries -= 1
                    time.sleep(10)
            except Exception as exc:
                msg = f"Could not connect to database.\n{exc}"
                raise DataSafeHavenAzureError(msg) from exc
        return connection

    def load_sql(
        self, filepath: PathType, mustache_values: dict[str, str] | None = None
    ) -> str:
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
        self,
        filepaths: Sequence[PathType],
        mustache_values: dict[str, Any] | None = None,
    ) -> list[list[str]]:
        """Execute scripts on the PostgreSQL server."""
        outputs: list[list[str]] = []
        connection: psycopg.Connection | None = None
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
                cursor.execute(query=commands.encode())
                if cursor.statusmessage and "SELECT" in cursor.statusmessage:
                    outputs += [[str(msg) for msg in msg_tuple] for msg_tuple in cursor]

            # Commit changes
            connection.commit()
            self.logger.info(f"Finished running {len(filepaths)} SQL scripts.")
        except (Exception, psycopg.Error) as exc:
            msg = f"Error while connecting to PostgreSQL.\n{exc}"
            raise DataSafeHavenAzureError(msg) from exc
        finally:
            # Close the connection if it is open
            if connection:
                if cursor:
                    cursor.close()
                connection.close()
            # Remove temporary firewall rules
            self.set_database_access("disabled")
        return outputs

    def set_database_access(self, action: str) -> None:
        """Enable/disable database access to the PostgreSQL server."""
        if action == "enabled":
            self.logger.debug(
                f"Adding temporary firewall rule for [green]{self.current_ip}[/]...",
            )
            # NB. We would like to enable public_network_access at this point but this
            # is not currently supported by the flexibleServer API
            self.wait(
                self.db_client.firewall_rules.begin_create_or_update(
                    self.resource_group_name,
                    self.server_name,
                    f"AllowConfigurationUpdate-{self.rule_suffix}",
                    FirewallRule(
                        start_ip_address=self.current_ip, end_ip_address=self.current_ip
                    ),
                )
            )
            self.db_connection(n_retries=5)
            self.logger.info(
                f"Added temporary firewall rule for [green]{self.current_ip}[/].",
            )
        elif action == "disabled":
            self.logger.debug(
                f"Removing all firewall rule(s) from [green]{self.server_name}[/]...",
            )
            rules = cast(
                list[FirewallRule],
                self.db_client.firewall_rules.list_by_server(
                    self.resource_group_name, self.server_name
                ),
            )

            # Delete all named firewall rules
            rule_names = [str(rule.name) for rule in rules if rule.name]
            for rule_name in rule_names:
                self.wait(
                    self.db_client.firewall_rules.begin_delete(
                        self.resource_group_name, self.server_name, rule_name
                    )
                )

            # NB. We would like to disable public_network_access at this point but this
            # is not currently supported by the flexibleServer API
            if len(rule_names) == len(rules):
                self.logger.info(
                    f"Removed all firewall rule(s) from [green]{self.server_name}[/].",
                )
            else:
                self.logger.warning(
                    f"Unable to remove all firewall rule(s) from [green]{self.server_name}[/].",
                )
        else:
            msg = f"Database access action {action} was not recognised."
            raise DataSafeHavenInputError(msg)
        self.db_server_ = None  # Force refresh of self.db_server
        public_network_access = (
            self.db_server.network.public_network_access
            if self.db_server.network
            else "UNKNOWN"
        )
        self.logger.debug(
            f"Public network access to [green]{self.server_name}[/]"
            f" is [green]{public_network_access}[/]."
        )
