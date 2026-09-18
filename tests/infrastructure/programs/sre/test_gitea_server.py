from typing import Any

import pulumi
import pulumi.runtime

from data_safe_haven.infrastructure.components import PostgresqlDatabaseComponent
from data_safe_haven.infrastructure.programs.sre.gitea_server import (
    SREGiteaServerComponent,
    SREGiteaServerProps,
)


class TestSREGiteaServerComponent:
    @pulumi.runtime.test  # type: ignore
    def test_creation(self, gitea_server_component: SREGiteaServerComponent) -> None:
        """Basic test to ensure the component is being created correctly"""
        assert isinstance(gitea_server_component, SREGiteaServerComponent)

    @pulumi.runtime.test  # type: ignore
    def test_min_interval_is_one_minute(
        self, gitea_server_component: SREGiteaServerComponent
    ) -> Any:
        """Check that Gitea always accepts a mirror interval down to 1 minute"""

        def check(containers: list[Any]) -> None:
            gitea = next(c for c in containers if c["name"] == "gitea")
            min_interval = next(
                env["value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__mirror__MIN_INTERVAL"
            )
            assert min_interval == "1m"

        return pulumi.Output.from_input(
            gitea_server_component.container_group.containers
        ).apply(check)

    @pulumi.runtime.test  # type: ignore
    def test_database_password_matches_props(
        self,
        gitea_server_component: SREGiteaServerComponent,
        gitea_server_props: SREGiteaServerProps,
    ) -> Any:
        """Check that the database password passed via props reaches the container"""

        def check(inputs: list[Any]) -> None:
            containers, expected_password = inputs
            gitea = next(c for c in containers if c["name"] == "gitea")
            actual_password = next(
                env["secure_value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__database__PASSWD"
            )
            assert actual_password == expected_password

        return pulumi.Output.from_input(
            [
                gitea_server_component.container_group.containers,
                gitea_server_props.db_server_shared_password,
            ]
        ).apply(check)

    @pulumi.runtime.test  # type: ignore
    def test_database_details_match_shared_db(
        self,
        gitea_server_component: SREGiteaServerComponent,
        db_server_shared: PostgresqlDatabaseComponent,
    ) -> Any:
        """Check that the Gitea container connects to the shared database fixture"""

        def check(inputs: dict[str, Any]) -> None:
            gitea = next(c for c in inputs["containers"] if c["name"] == "gitea")
            host = next(
                env["value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__database__HOST"
            )
            username = next(
                env["value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__database__USER"
            )
            assert host == inputs["expected_host"]
            assert username == inputs["expected_username"]

        return pulumi.Output.from_input(
            {
                "containers": gitea_server_component.container_group.containers,
                "expected_host": db_server_shared.private_ip_address,
                "expected_username": db_server_shared.db_server.administrator_login,
            }
        ).apply(check)
