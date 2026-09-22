from typing import Any

import pulumi
import pulumi.runtime

from data_safe_haven.infrastructure.programs.sre.gitea_server import (
    SREGiteaServerComponent,
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
    def test_update_mirrors_schedule_is_every_minute(
        self, gitea_server_component: SREGiteaServerComponent
    ) -> Any:
        """Check that Gitea's own update_mirrors cron task runs every minute"""

        def check(containers: list[Any]) -> None:
            gitea = next(c for c in containers if c["name"] == "gitea")
            schedule = next(
                env["value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__cron_0x2E_update_mirrors__SCHEDULE"
            )
            assert schedule == "@every 1m"

        return pulumi.Output.from_input(
            gitea_server_component.container_group.containers
        ).apply(check)

    @pulumi.runtime.test  # type: ignore
    def test_admin_password_stored(
        self,
        gitea_server_component: SREGiteaServerComponent,
        gitea_admin_password: str,
    ) -> Any:
        def check(containers: list[Any]) -> None:
            gitea = next(c for c in containers if c["name"] == "gitea")
            admin_password = next(
                env["secure_value"]
                for env in gitea["environment_variables"]
                if env["name"] == "ADMIN_SERVER_PASSWORD"
            )
            assert admin_password == gitea_admin_password

        return pulumi.Output.from_input(
            gitea_server_component.container_group.containers
        ).apply(check)

    @pulumi.runtime.test  # type: ignore
    def test_workspace_password_stored(
        self,
        gitea_server_component: SREGiteaServerComponent,
        gitea_user_password: str,
    ) -> Any:
        def check(containers: list[Any]) -> None:
            gitea = next(c for c in containers if c["name"] == "gitea")
            workspace_password = next(
                env["secure_value"]
                for env in gitea["environment_variables"]
                if env["name"] == "WORKSPACE_SERVER_PASSWORD"
            )
            assert workspace_password == gitea_user_password

        return pulumi.Output.from_input(
            gitea_server_component.container_group.containers
        ).apply(check)
